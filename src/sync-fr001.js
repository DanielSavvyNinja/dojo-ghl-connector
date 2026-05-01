/**
 * FR-001 sync extensions
 *
 * New sync paths and helpers added by FR-001 (data model couplings).
 * Mixed into the existing GHLSync class via Object.assign or wired
 * directly as standalone helpers.
 *
 * Adds:
 *   - syncTechniciansFromGHL  (FR-001 #3 — Tech ↔ Employees / GHL Team)
 *   - recordManualPayment     (FR-001 #4 — Mobile cash/check entry)
 *   - pullInvoiceStatusFromGHL (FR-001 #4 — Invoice status sync)
 *   - handleGHLInvoiceWebhook (FR-001 #4 — Invoice paid/voided webhook)
 *   - handleGHLPaymentWebhook (FR-001 #4 — Payment collected webhook)
 *   - getTaxRateForItem        (Decision #5 — tax pulled from price book)
 */

// ─── TECHNICIAN SYNC (FR-001 #3) ──────────────────────────────────
/**
 * Pull users from GHL Team API into local technicians table.
 * Single source of truth: a tech in GHL = a tech assignable in dispatch.
 * Tech removed from GHL = is_active=false (don't delete, preserve history).
 *
 * @param {object} ghl - GHL client (must implement getUsers or getLocationUsers)
 * @param {object} store - Supabase store
 * @param {string} locationId - GHL location ID (sub-account)
 * @returns {Promise<Array>} list of upserted technician rows
 */
export async function syncTechniciansFromGHL(ghl, store, locationId) {
  if (!ghl || !store) return [];

  // GHL exposes users at the location level; method name may vary
  const usersResp = ghl.getLocationUsers
    ? await ghl.getLocationUsers(locationId)
    : await ghl.getUsers({ locationId });

  const ghlUsers = usersResp?.users || usersResp || [];
  const liveGhlIds = new Set();
  const synced = [];

  for (const u of ghlUsers) {
    liveGhlIds.add(u.id);
    const tech = {
      ghl_user_id: u.id,
      name: `${u.firstName || ''} ${u.lastName || ''}`.trim() || u.name || u.email,
      email: u.email,
      phone: u.phone,
      role: u.role || 'technician',
      is_active: true,
      updated_at: new Date().toISOString(),
    };
    const saved = await store.upsertTechnician(tech);
    synced.push(saved);
  }

  // Mark techs not in the GHL list as inactive (don't delete)
  if (store.getTechnicians) {
    const localTechs = await store.getTechnicians();
    for (const t of localTechs) {
      if (t.ghl_user_id && !liveGhlIds.has(t.ghl_user_id) && t.is_active) {
        await store.updateTechnician(t.id, { is_active: false, updated_at: new Date().toISOString() });
      }
    }
  }

  return synced;
}

// ─── MANUAL PAYMENT (FR-001 #4 — mobile cash/check) ──────────────
/**
 * Record a manual cash/check payment collected in the field by a tech.
 * No GHL processor roundtrip — directly creates a payments row with
 * status='paid'. The corresponding invoice gets status='paid' if the
 * payment covers the invoice total.
 *
 * @param {object} store - Supabase store
 * @param {object} input - { invoice_id, amount, method ('cash'|'check'),
 *                           collected_by, collected_at, notes, location_id }
 * @returns {Promise<{payment, invoice}>}
 */
export async function recordManualPayment(store, input) {
  if (!store) throw new Error('store required');
  if (!input?.invoice_id) throw new Error('invoice_id required');
  if (!['cash', 'check'].includes(input.method)) {
    throw new Error('method must be cash or check for manual payments');
  }

  const payment = await store.createPayment({
    invoice_id: input.invoice_id,
    location_id: input.location_id,
    amount: input.amount,
    method: input.method,
    status: 'paid',
    processor: null,
    collected_by: input.collected_by || null,
    collected_at: input.collected_at || new Date().toISOString(),
    notes: input.notes || null,
  });

  // Check whether the invoice is now fully paid and update its status
  if (store.getInvoice && store.getPaymentsForInvoice) {
    const invoice = await store.getInvoice(input.invoice_id);
    const payments = await store.getPaymentsForInvoice(input.invoice_id);
    const paidTotal = payments
      .filter(p => p.status === 'paid')
      .reduce((s, p) => s + Number(p.amount || 0), 0);

    if (invoice && paidTotal >= Number(invoice.total || 0)) {
      await store.updateInvoice(invoice.id, {
        status: 'paid',
        paid_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
      return { payment, invoice: { ...invoice, status: 'paid' } };
    }
    return { payment, invoice };
  }

  return { payment };
}

// ─── INVOICE STATUS PULL (FR-001 #4) ──────────────────────────────
/**
 * Pull invoice status from GHL for invoices that have a ghl_invoice_id
 * but aren't yet marked paid/voided locally. Useful for a periodic
 * reconciliation job in case webhooks were missed.
 */
export async function pullInvoiceStatusFromGHL(ghl, store) {
  if (!ghl || !store?.getInvoicesNeedingStatusSync) return [];

  const invoices = await store.getInvoicesNeedingStatusSync();
  const updated = [];

  for (const inv of invoices) {
    if (!inv.ghl_invoice_id) continue;
    try {
      const ghlInv = await ghl.getInvoice(inv.ghl_invoice_id);
      const newStatus = mapGHLInvoiceStatus(ghlInv.status || ghlInv.state);
      if (newStatus && newStatus !== inv.status) {
        const saved = await store.updateInvoice(inv.id, {
          status: newStatus,
          paid_at: newStatus === 'paid' ? (ghlInv.paidAt || new Date().toISOString()) : inv.paid_at,
          updated_at: new Date().toISOString(),
        });
        updated.push(saved);
      }
    } catch (err) {
      // Swallow individual invoice errors so one bad row doesn't break the batch
      console.warn(`pullInvoiceStatusFromGHL: failed for invoice ${inv.id}`, err?.message);
    }
  }

  return updated;
}

function mapGHLInvoiceStatus(ghlStatus) {
  if (!ghlStatus) return null;
  const s = String(ghlStatus).toLowerCase();
  if (s === 'paid') return 'paid';
  if (s === 'sent') return 'sent';
  if (s === 'draft') return 'draft';
  if (s === 'voided' || s === 'void' || s === 'cancelled') return 'voided';
  if (s === 'overdue') return 'overdue';
  return null;
}

// ─── WEBHOOK HANDLERS (FR-001 #4) ─────────────────────────────────
/**
 * Handle a GHL invoice webhook event.
 * Wire this to a /webhooks/ghl/invoice route in your hosting platform.
 *
 * Expected event shapes (GHL is inconsistent across endpoints):
 *   { type: 'invoice.paid', invoiceId, paidAt }
 *   { type: 'invoice.voided', invoiceId }
 *   { type: 'invoice.sent', invoiceId, sentAt }
 */
export async function handleGHLInvoiceWebhook(store, event) {
  if (!store || !event?.invoiceId) return null;

  const inv = await store.getInvoiceByGhlId(event.invoiceId);
  if (!inv) return null; // unknown invoice — likely created elsewhere

  const updates = { updated_at: new Date().toISOString() };

  switch (event.type) {
    case 'invoice.paid':
      updates.status = 'paid';
      updates.paid_at = event.paidAt || new Date().toISOString();
      break;
    case 'invoice.voided':
      updates.status = 'voided';
      break;
    case 'invoice.sent':
      updates.status = 'sent';
      updates.sent_at = event.sentAt || new Date().toISOString();
      break;
    default:
      return null;
  }

  return store.updateInvoice(inv.id, updates);
}

/**
 * Handle a GHL payment webhook event.
 * Creates a row in the payments table linked to the invoice.
 */
export async function handleGHLPaymentWebhook(store, event) {
  if (!store || !event?.invoiceId || !event?.paymentId) return null;

  const inv = await store.getInvoiceByGhlId(event.invoiceId);
  if (!inv) return null;

  // Idempotency: bail if we've already recorded this payment
  if (store.getPaymentByGhlId) {
    const existing = await store.getPaymentByGhlId(event.paymentId);
    if (existing) return existing;
  }

  return store.createPayment({
    invoice_id: inv.id,
    location_id: inv.location_id,
    ghl_payment_id: event.paymentId,
    amount: event.amount,
    method: event.method || 'card',
    status: event.status || 'paid',
    processor: 'ghl_payments',
    processor_transaction_id: event.transactionId || null,
    collected_at: event.collectedAt || event.paidAt || new Date().toISOString(),
    notes: event.notes || null,
  });
}

// ─── TAX HELPERS (Decision #5) ────────────────────────────────────
/**
 * Compute the effective tax rate for a price book item.
 * Reads price_book.tax_rate first; falls back to location_settings.tax_rate
 * if the item is taxable but has no item-level rate set.
 */
export async function getTaxRateForItem(store, priceBookId, locationId) {
  if (!store || !priceBookId) return 0;

  const item = await store.getPriceBookItem(priceBookId);
  if (!item || item.is_taxable === false) return 0;

  if (Number(item.tax_rate) > 0) return Number(item.tax_rate);

  if (locationId && store.getLocationSettings) {
    const settings = await store.getLocationSettings(locationId);
    return Number(settings?.tax_rate || 0);
  }

  return 0;
}

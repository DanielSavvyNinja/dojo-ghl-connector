/**
 * GHL Sync Service — Bi-directional sync between Supabase and GHL
 *
 * Handles:
 *   - Contact sync: GHL contacts ↔ local customers table
 *   - Opportunity sync: GHL opportunities ↔ local jobs table
 *   - Calendar sync: GHL calendar events ↔ job schedule
 *   - Invoice push: Local invoices → GHL invoices
 *   - Workflow triggers: Job stage changes → GHL workflow triggers
 */

export class GHLSync {
  constructor(ghl, store) {
    this.ghl = ghl
    this.store = store
  }

  // ─── CONTACT SYNC ──────────────────────────────────────────

  /** Pull GHL contacts into local customers table */
  async syncContactsFromGHL(limit = 100) {
    if (!this.ghl) return []
    const { contacts } = await this.ghl.getContacts({ limit })
    const synced = []
    for (const c of contacts || []) {
      const customer = {
        ghl_contact_id: c.id,
        name: `${c.firstName || ''} ${c.lastName || ''}`.trim(),
        email: c.email,
        phone: c.phone,
        address: c.address1,
        city: c.city,
        state: c.state,
        zip: c.postalCode,
        source: c.source,
        tags: c.tags,
        updated_at: new Date().toISOString(),
      }
      if (this.store) {
        const saved = await this.store.upsertCustomer(customer)
        synced.push(saved)
      }
    }
    return synced
  }

  /** Push a local customer to GHL as a contact */
  async pushCustomerToGHL(customer) {
    if (!this.ghl) return null
    const nameParts = (customer.name || '').split(' ')
    const contactData = {
      firstName: nameParts[0] || '',
      lastName: nameParts.slice(1).join(' ') || '',
      email: customer.email,
      phone: customer.phone,
      address1: customer.address,
      city: customer.city,
      state: customer.state,
      postalCode: customer.zip,
      source: customer.source || 'Dojo FS Command',
      tags: ['dvs-customer'],
    }

    if (customer.ghl_contact_id) {
      await this.ghl.updateContact(customer.ghl_contact_id, contactData)
      return customer.ghl_contact_id
    } else {
      const result = await this.ghl.createContact(contactData)
      if (this.store && result.contact?.id) {
        await this.store.upsertCustomer({ ...customer, ghl_contact_id: result.contact.id })
      }
      return result.contact?.id
    }
  }

  // ─── JOB / OPPORTUNITY SYNC ────────────────────────────────

  /** Map local job stage to GHL pipeline stage ID */
  getGHLStageMapping(pipelineStages, localStage) {
    const stageMap = {
      'lead': 'New Lead',
      'estimate': 'Estimate Sent',
      'approved': 'Approved',
      'scheduled': 'Scheduled',
      'dispatched': 'Dispatched',
      'in-progress': 'In Progress',
      'completed': 'Completed',
      'invoiced': 'Invoiced',
      'paid': 'Paid',
      'cancelled': 'Cancelled',
    }
    const ghlStageName = stageMap[localStage] || localStage
    return pipelineStages.find(s => s.name === ghlStageName)?.id
  }

  /** Push job to GHL as an opportunity */
  async pushJobToGHL(job, pipelineId, pipelineStages) {
    if (!this.ghl) return null
    const stageId = this.getGHLStageMapping(pipelineStages, job.stage)
    const total = (job.lineItems || job.job_line_items || []).reduce((s, li) => s + (li.qty * li.price), 0)

    const oppData = {
      pipelineId,
      pipelineStageId: stageId,
      name: `${job.id} — ${job.customerName || job.customer_name}`,
      monetaryValue: total,
      contactId: job.ghl_contact_id,
      status: job.stage === 'cancelled' ? 'lost' : (job.stage === 'paid' ? 'won' : 'open'),
    }

    if (job.ghl_opportunity_id) {
      await this.ghl.updateOpportunity(job.ghl_opportunity_id, oppData)
      return job.ghl_opportunity_id
    } else {
      const result = await this.ghl.createOpportunity(oppData)
      if (this.store && result.opportunity?.id) {
        await this.store.updateJob(job.id, { ghl_opportunity_id: result.opportunity.id })
      }
      return result.opportunity?.id
    }
  }

  /** Update GHL opportunity stage when local job stage changes */
  async syncJobStageToGHL(job, newStage, pipelineId, pipelineStages) {
    if (!this.ghl || !job.ghl_opportunity_id) return
    const stageId = this.getGHLStageMapping(pipelineStages, newStage)
    if (!stageId) return

    await this.ghl.updateOpportunity(job.ghl_opportunity_id, {
      pipelineStageId: stageId,
      status: newStage === 'cancelled' ? 'lost' : (newStage === 'paid' ? 'won' : 'open'),
    })
  }

  // ─── CALENDAR SYNC ─────────────────────────────────────────

  /** Push scheduled job to GHL calendar */
  async pushJobToCalendar(job, calendarId) {
    if (!this.ghl || !job.scheduledDate) return null
    const startTime = new Date(`${job.scheduledDate}T${job.scheduledTime || '09:00'}:00`)
    const duration = (job.lineItems || job.job_line_items || []).reduce((d, li) => {
      return d + ((li.duration || 60) * (li.qty || 1))
    }, 0) || 60
    const endTime = new Date(startTime.getTime() + duration * 60000)

    const eventData = {
      title: `${job.id} — ${job.customerName || job.customer_name}`,
      startTime: startTime.toISOString(),
      endTime: endTime.toISOString(),
      description: `Service: ${(job.lineItems || []).map(li => li.serviceId || li.service_id).join(', ')}\nAddress: ${job.address}, ${job.city}`,
      contactId: job.ghl_contact_id,
      assignedUserId: job.ghl_tech_user_id,
    }

    return this.ghl.createCalendarEvent(calendarId, eventData)
  }

  // ─── INVOICE PUSH ──────────────────────────────────────────

  /** Push invoice to GHL */
  async pushInvoiceToGHL(job) {
    if (!this.ghl || !job.ghl_contact_id) return null
    const lineItems = (job.lineItems || job.job_line_items || []).map(li => ({
      name: li.serviceId || li.service_id || li.name,
      description: li.description || '',
      quantity: li.qty || 1,
      unitPrice: li.price * 100, // GHL uses cents
    }))

    const invoiceData = {
      contactId: job.ghl_contact_id,
      name: `Invoice for ${job.customerName || job.customer_name}`,
      items: lineItems,
      currency: 'USD',
      dueDate: new Date(Date.now() + 30 * 86400000).toISOString(), // Net 30
    }

    const result = await this.ghl.createInvoice(invoiceData)
    if (this.store && result?.id) {
      await this.store.createInvoice({
        job_id: job.id,
        ghl_invoice_id: result.id,
        amount: (job.lineItems || job.job_line_items || []).reduce((s, li) => s + (li.qty * li.price), 0),
        status: 'sent',
        sent_at: new Date().toISOString(),
      })
    }
    return result
  }

  // ─── WORKFLOW TRIGGERS ─────────────────────────────────────

  /** Add tag to GHL contact to trigger automations */
  async triggerWorkflow(contactId, triggerTag) {
    if (!this.ghl || !contactId) return
    await this.ghl.addContactTag(contactId, [triggerTag])
  }

  /** Common workflow triggers */
  async onJobCompleted(job) {
    if (job.ghl_contact_id) {
      await this.triggerWorkflow(job.ghl_contact_id, 'job-completed')
      await this.ghl.addContactNote(job.ghl_contact_id,
        `Job ${job.id} completed on ${job.completedDate || new Date().toISOString().split('T')[0]}`)
    }
  }

  async onInvoiceSent(job) {
    if (job.ghl_contact_id) {
      await this.triggerWorkflow(job.ghl_contact_id, 'invoice-sent')
    }
  }

  async onPaymentReceived(job) {
    if (job.ghl_contact_id) {
      await this.triggerWorkflow(job.ghl_contact_id, 'payment-received')
    }
  }

  async onNewLead(job) {
    if (job.ghl_contact_id) {
      await this.triggerWorkflow(job.ghl_contact_id, 'new-dvs-lead')
    }
  }

  async onReviewRequested(job) {
    if (job.ghl_contact_id) {
      await this.triggerWorkflow(job.ghl_contact_id, 'review-request')
    }
  }
}

export function createSync(ghl, store) {
  return new GHLSync(ghl, store)
}

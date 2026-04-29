-- Migration 002: FR-001 data model couplings
-- Project: the-dojo-dvs (ybujjznnjfzjbjfegmdj)
-- Authorized: Daniel 2026-04-28
-- Status: Applied to live DB on 2026-04-28
--
-- FR-001 items addressed:
--   #2  Service Type <-> Products: job_line_items.price_book_id FK
--   #4  Invoicing & Payments:    invoices.customer_id FK + payments.updated_at + check constraints
--   Decision #5  Tax model:       price_book.tax_rate, price_book.is_taxable
--   Schema hygiene:              RLS hardening on prototype tables, updated_at trigger function + triggers
--
-- FR-001 #1 (Jobs <-> Contacts) and #3 (Tech <-> Employees) were already satisfied by migration 001:
--   jobs.customer_id  UUID -> customers(id)   (treat as 'contact_id' semantically in UI/docs)
--   jobs.tech_id      UUID -> technicians(id) (treat as 'technician_id' semantically in UI/docs)
-- No schema change needed -- UI work in apps must read these as the source of truth and stop using
-- the denormalized free-text fields on jobs (customer_name, email, phone, address, etc.) which
-- are kept as a read cache and will be dropped in a follow-up migration after UI cutover.

-- ============================================================
-- 1. job_line_items.price_book_id (FR-001 #2: Service Type <-> Products)
-- ============================================================
ALTER TABLE job_line_items
  ADD COLUMN IF NOT EXISTS price_book_id UUID REFERENCES price_book(id);

-- Backfill from existing text-keyed service_id
UPDATE job_line_items jli
SET price_book_id = pb.id
FROM price_book pb
WHERE jli.service_id = pb.service_id
  AND jli.price_book_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_job_line_items_price_book_id
  ON job_line_items(price_book_id);

-- ============================================================
-- 2. invoices.customer_id (FR-001 #4: Invoicing - direct customer link)
-- ============================================================
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id);

-- Backfill from jobs link
UPDATE invoices i
SET customer_id = j.customer_id
FROM jobs j
WHERE i.job_id = j.id
  AND i.customer_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_invoices_customer_id
  ON invoices(customer_id);

-- NOTE: invoices.line_items JSONB intentionally NOT added.
-- The existing normalized invoice_line_items table serves this purpose
-- and aligns with the existing job_line_items pattern.

-- ============================================================
-- 3. payments.updated_at + CHECK constraints (FR-001 #4: Payments)
-- ============================================================
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'payments_method_check'
      AND conrelid = 'payments'::regclass
  ) THEN
    ALTER TABLE payments ADD CONSTRAINT payments_method_check
      CHECK (method IN ('cash','check','card','ach','ghl_link','terminal','other'));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'payments_status_check'
      AND conrelid = 'payments'::regclass
  ) THEN
    ALTER TABLE payments ADD CONSTRAINT payments_status_check
      CHECK (status IN ('pending','paid','failed','refunded','voided'));
  END IF;
END $$;

-- NOTE: spec asked for paid_at, existing column is collected_at.
-- Standardize on collected_at everywhere; UI/code reads collected_at,
-- treat 'paid_at' as a synonym in docs only. No generated column added
-- to avoid write-path conflicts (generated columns are read-only).

-- ============================================================
-- 4. price_book tax columns (Decision #5: tax pulled from price book)
-- ============================================================
ALTER TABLE price_book
  ADD COLUMN IF NOT EXISTS tax_rate NUMERIC DEFAULT 0;

ALTER TABLE price_book
  ADD COLUMN IF NOT EXISTS is_taxable BOOLEAN DEFAULT true;

-- App code reads price_book.tax_rate first; falls back to location_settings.tax_rate
-- if the price_book row has is_taxable=true and tax_rate=0. Job-level override
-- happens in app code, not schema.

-- ============================================================
-- 5. RLS hardening (replace 'Allow all for anon' with 'Allow all for authenticated')
-- ============================================================
DROP POLICY IF EXISTS "Allow all for anon" ON payments;
CREATE POLICY "Allow all for authenticated" ON payments
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for anon" ON invoice_line_items;
CREATE POLICY "Allow all for authenticated" ON invoice_line_items
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for anon" ON location_settings;
CREATE POLICY "Allow all for authenticated" ON location_settings
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ============================================================
-- 6. updated_at trigger function + triggers
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_customers_updated_at ON customers;
CREATE TRIGGER update_customers_updated_at
  BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_price_book_updated_at ON price_book;
CREATE TRIGGER update_price_book_updated_at
  BEFORE UPDATE ON price_book
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_jobs_updated_at ON jobs;
CREATE TRIGGER update_jobs_updated_at
  BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_invoices_updated_at ON invoices;
CREATE TRIGGER update_invoices_updated_at
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_payments_updated_at ON payments;
CREATE TRIGGER update_payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_location_settings_updated_at ON location_settings;
CREATE TRIGGER update_location_settings_updated_at
  BEFORE UPDATE ON location_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

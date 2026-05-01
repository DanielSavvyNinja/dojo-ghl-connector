-- TEST PASTE OK
SELECT 1;
-- migrations/002_fr001_couplings.sql
-- FR-001: Data-model couplings for Jobs<->Contacts, Service<->PriceBook,
-- Tech<->Employees, Jobs<->Invoicing&Payments. Idempotent / additive.
-- Targets the schema state observed in the-dojo-dvs on 2026-04-28.

-- =====================================================================
-- 1. FR-001 #2: job_line_items.price_book_id UUID FK -> price_book(id)
-- (Existing FK is via service_id text; this adds the canonical UUID FK.)
-- =====================================================================
ALTER TABLE public.job_line_items
  ADD COLUMN IF NOT EXISTS price_book_id UUID REFERENCES public.price_book(id);

UPDATE public.job_line_items jli
SET price_book_id = pb.id
FROM public.price_book pb
WHERE jli.service_id = pb.service_id
  AND jli.price_book_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_job_line_items_price_book_id
  ON public.job_line_items(price_book_id);

COMMENT ON COLUMN public.job_line_items.price_book_id IS
  'FR-001 #2: canonical UUID FK to price_book(id). Replaces legacy service_id text key.';

-- =====================================================================
-- 2. FR-001 #4: invoices.customer_id FK + invoices.updated_at
-- (line_items live in the existing normalized invoice_line_items table;
--  no JSONB blob needed.)
-- =====================================================================
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES public.customers(id);

ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE public.invoices i
SET customer_id = j.customer_id
FROM public.jobs j
WHERE i.job_id = j.id
  AND i.customer_id IS NULL
  AND j.customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_invoices_customer_id
  ON public.invoices(customer_id);

COMMENT ON COLUMN public.invoices.customer_id IS
  'FR-001 #4: direct FK to customers(id). Line items live in invoice_line_items.';

-- =====================================================================
-- 3. FR-001 #4: payments hardening
-- - paid_at as generated alias of collected_at when status=paid (spec naming)
-- - updated_at column for trigger
-- - CHECK constraints on method (incl. cash/check for mobile manual log)
--   and status
-- - indexes for lookup paths used by dispatch board / mobile completion flow
-- =====================================================================
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ
  GENERATED ALWAYS AS (
    CASE WHEN status = 'paid' THEN collected_at ELSE NULL END
  ) STORED;

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_method_check
  CHECK (
    method IS NULL OR method IN
    ('cash','check','card','ach','ghl_link','terminal','other')
  );

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_status_check
  CHECK (status IN ('pending','paid','failed','refunded','voided'));

CREATE INDEX IF NOT EXISTS idx_payments_invoice_id ON public.payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_collected_at ON public.payments(collected_at);

COMMENT ON COLUMN public.payments.paid_at IS
  'FR-001 #4: generated alias of collected_at when status=paid. Spec naming.';

-- =====================================================================
-- 4. Decision #5: per-item tax on price_book
-- (UI/code: read price_book.tax_rate first, fall back to
-- location_settings.tax_rate. Job-level override is app-layer.)
-- =====================================================================
ALTER TABLE public.price_book
  ADD COLUMN IF NOT EXISTS tax_rate NUMERIC DEFAULT 0;

ALTER TABLE public.price_book
  ADD COLUMN IF NOT EXISTS is_taxable BOOLEAN DEFAULT true;

COMMENT ON COLUMN public.price_book.tax_rate IS
  'FR-001 decision #5: per-item tax rate (e.g. 0.0875 for 8.75%). Falls back to location_settings.tax_rate. Ignored when is_taxable=false.';

COMMENT ON COLUMN public.price_book.is_taxable IS
  'FR-001 decision #5: when false, tax_rate is ignored (tax-exempt services).';

-- =====================================================================
-- 5. RLS hardening: payments / invoice_line_items / location_settings
-- were created with 'Allow all for anon (qual:true)'. Match the 001
-- pattern of authenticated-only access.
-- =====================================================================
DROP POLICY IF EXISTS "Allow all for anon" ON public.payments;
CREATE POLICY "Allow all for authenticated"
  ON public.payments
  FOR ALL TO public
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Allow all for anon" ON public.invoice_line_items;
CREATE POLICY "Allow all for authenticated"
  ON public.invoice_line_items
  FOR ALL TO public
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Allow all for anon" ON public.location_settings;
CREATE POLICY "Allow all for authenticated"
  ON public.location_settings
  FOR ALL TO public
  USING (auth.role() = 'authenticated');

-- =====================================================================
-- 6. updated_at trigger function + triggers
-- (No triggers exist in public schema; updated_at columns weren't being
-- maintained.)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_customers_updated_at ON public.customers;
CREATE TRIGGER update_customers_updated_at
  BEFORE UPDATE ON public.customers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_price_book_updated_at ON public.price_book;
CREATE TRIGGER update_price_book_updated_at
  BEFORE UPDATE ON public.price_book
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_jobs_updated_at ON public.jobs;
CREATE TRIGGER update_jobs_updated_at
  BEFORE UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_invoices_updated_at ON public.invoices;
CREATE TRIGGER update_invoices_updated_at
  BEFORE UPDATE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_payments_updated_at ON public.payments;
CREATE TRIGGER update_payments_updated_at
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_location_settings_updated_at ON public.location_settings;
CREATE TRIGGER update_location_settings_updated_at
  BEFORE UPDATE ON public.location_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- migrations/002_fr001_couplings.sql
-- FR-001: Data-model couplings for Jobs<->Contacts, Service<->PriceBook,
-- Tech<->Employees, Jobs<->Invoicing&Payments. Idempotent / additive.
-- Targets the schema state observed in the-dojo-dvs on 2026-04-28.

-- =====================================================================
-- 1. FR-001 #2: job_line_items.price_book_id UUID FK -> price_book(id)
-- (Existing FK is via service_id text; this adds the canonical UUID FK.)
-- =====================================================================
ALTER TABLE public.job_line_items
  ADD COLUMN IF NOT EXISTS price_book_id UUID REFERENCES public.price_book(id);

UPDATE public.job_line_items jli
SET price_book_id = pb.id
FROM public.price_book pb
WHERE jli.service_id = pb.service_id
  AND jli.price_book_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_job_line_items_price_book_id
  ON public.job_line_items(price_book_id);

COMMENT ON COLUMN public.job_line_items.price_book_id IS
  'FR-001 #2: canonical UUID FK to price_book(id). Replaces legacy service_id text key.';

-- =====================================================================
-- 2. FR-001 #4: invoices.customer_id FK + invoices.updated_at
-- (line_items live in the existing normalized invoice_line_items table;
--  no JSONB blob needed.)
-- =====================================================================
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES public.customers(id);

ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE public.invoices i
SET customer_id = j.customer_id
FROM public.jobs j
WHERE i.job_id = j.id
  AND i.customer_id IS NULL
  AND j.customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_invoices_customer_id
  ON public.invoices(customer_id);

COMMENT ON COLUMN public.invoices.customer_id IS
  'FR-001 #4: direct FK to customers(id). Line items live in invoice_line_items.';

-- =====================================================================
-- 3. FR-001 #4: payments hardening
-- =====================================================================
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ
  GENERATED ALWAYS AS (
    CASE WHEN status = 'paid' THEN collected_at ELSE NULL END
  ) STORED;

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_method_check
  CHECK (
    method IS NULL OR method IN
    ('cash','check','card','ach','ghl_link','terminal','other')
  );

ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_status_check
  CHECK (status IN ('pending','paid','failed','refunded','voided'));

CREATE INDEX IF NOT EXISTS idx_payments_invoice_id ON public.payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_collected_at ON public.payments(collected_at);

COMMENT ON COLUMN public.payments.paid_at IS
  'FR-001 #4: generated alias of collected_at when status=paid. Spec naming.';

-- =====================================================================
-- 4. Decision #5: per-item tax on price_book
-- =====================================================================
ALTER TABLE public.price_book
  ADD COLUMN IF NOT EXISTS tax_rate NUMERIC DEFAULT 0;

ALTER TABLE public.price_book
  ADD COLUMN IF NOT EXISTS is_taxable BOOLEAN DEFAULT true;

COMMENT ON COLUMN public.price_book.tax_rate IS
  'FR-001 decision #5: per-item tax rate. Falls back to location_settings.tax_rate. Ignored when is_taxable=false.';

COMMENT ON COLUMN public.price_book.is_taxable IS
  'FR-001 decision #5: when false, tax_rate is ignored (tax-exempt services).';

-- =====================================================================
-- 5. RLS hardening: payments / invoice_line_items / location_settings
-- =====================================================================
DROP POLICY IF EXISTS "Allow all for anon" ON public.payments;
CREATE POLICY "Allow all for authenticated"
  ON public.payments FOR ALL TO public
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Allow all for anon" ON public.invoice_line_items;
CREATE POLICY "Allow all for authenticated"
  ON public.invoice_line_items FOR ALL TO public
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Allow all for anon" ON public.location_settings;
CREATE POLICY "Allow all for authenticated"
  ON public.location_settings FOR ALL TO public
  USING (auth.role() = 'authenticated');

-- =====================================================================
-- 6. updated_at trigger function + triggers
-- =====================================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_customers_updated_at ON public.customers;
CREATE TRIGGER update_customers_updated_at
  BEFORE UPDATE ON public.customers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_price_book_updated_at ON public.price_book;
CREATE TRIGGER update_price_book_updated_at
  BEFORE UPDATE ON public.price_book
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_jobs_updated_at ON public.jobs;
CREATE TRIGGER update_jobs_updated_at
  BEFORE UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_invoices_updated_at ON public.invoices;
CREATE TRIGGER update_invoices_updated_at
  BEFORE UPDATE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_payments_updated_at ON public.payments;
CREATE TRIGGER update_payments_updated_at
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_location_settings_updated_at ON public.location_settings;
CREATE TRIGGER update_location_settings_updated_at
  BEFORE UPDATE ON public.location_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

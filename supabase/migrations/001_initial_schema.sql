-- Dojo FS Command — Initial Database Schema
-- Run this in your Supabase SQL Editor to create all required tables

-- ─── CUSTOMERS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ghl_contact_id TEXT UNIQUE,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  address TEXT,
  city TEXT,
  state TEXT DEFAULT 'CA',
  zip TEXT,
  property_type TEXT DEFAULT 'Single Family',
  source TEXT,
  tags TEXT[],
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── TECHNICIANS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS technicians (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ghl_user_id TEXT UNIQUE,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  avatar_initials TEXT,
  color TEXT DEFAULT '#3b82f6',
  status TEXT DEFAULT 'active',
  hourly_rate DECIMAL(10,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── PRICE BOOK ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS price_book (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  service_id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  category TEXT DEFAULT 'cleaning',
  price DECIMAL(10,2) NOT NULL,
  cost DECIMAL(10,2) DEFAULT 0,
  duration_minutes INT DEFAULT 60,
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── JOBS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  ghl_opportunity_id TEXT,
  ghl_contact_id TEXT,
  customer_id UUID REFERENCES customers(id),
  customer_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  address TEXT,
  city TEXT,
  state TEXT DEFAULT 'CA',
  zip TEXT,
  property_type TEXT DEFAULT 'Single Family',
  stage TEXT DEFAULT 'lead',
  tech_id UUID REFERENCES technicians(id),
  scheduled_date DATE,
  scheduled_time TIME,
  completed_date DATE,
  source TEXT,
  notes TEXT,
  invoice_number TEXT,
  invoice_sent_date DATE,
  paid_date DATE,
  payment_method TEXT,
  rating INT,
  review_text TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── JOB LINE ITEMS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_line_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  job_id TEXT REFERENCES jobs(id) ON DELETE CASCADE,
  service_id TEXT REFERENCES price_book(service_id),
  name TEXT,
  description TEXT,
  qty INT DEFAULT 1,
  price DECIMAL(10,2) NOT NULL,
  cost DECIMAL(10,2) DEFAULT 0,
  sort_order INT DEFAULT 0
);

-- ─── JOB PHOTOS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_photos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  job_id TEXT REFERENCES jobs(id) ON DELETE CASCADE,
  file_name TEXT,
  file_path TEXT,
  public_url TEXT,
  photo_type TEXT DEFAULT 'during', -- before, during, after
  caption TEXT,
  uploaded_by UUID REFERENCES technicians(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── JOB TIMELINE ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_timeline (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  job_id TEXT REFERENCES jobs(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  performed_by TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── INVOICES ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoices (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  job_id TEXT REFERENCES jobs(id),
  ghl_invoice_id TEXT,
  invoice_number TEXT,
  amount DECIMAL(10,2),
  tax DECIMAL(10,2) DEFAULT 0,
  total DECIMAL(10,2),
  status TEXT DEFAULT 'draft', -- draft, sent, paid, overdue, cancelled
  sent_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  due_date DATE,
  payment_method TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── TIME TRACKING ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS time_entries (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  job_id TEXT REFERENCES jobs(id),
  tech_id UUID REFERENCES technicians(id),
  clock_in TIMESTAMPTZ,
  clock_out TIMESTAMPTZ,
  break_minutes INT DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── CHECKLISTS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS checklist_templates (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  service_id TEXT,
  items JSONB NOT NULL DEFAULT '[]',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS job_checklists (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  job_id TEXT REFERENCES jobs(id) ON DELETE CASCADE,
  template_id UUID REFERENCES checklist_templates(id),
  items JSONB NOT NULL DEFAULT '[]',
  completed_at TIMESTAMPTZ,
  completed_by UUID REFERENCES technicians(id)
);

-- ─── INDEXES ─────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_jobs_stage ON jobs(stage);
CREATE INDEX IF NOT EXISTS idx_jobs_tech ON jobs(tech_id);
CREATE INDEX IF NOT EXISTS idx_jobs_date ON jobs(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_jobs_ghl_opp ON jobs(ghl_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_jobs_ghl_contact ON jobs(ghl_contact_id);
CREATE INDEX IF NOT EXISTS idx_customers_ghl ON customers(ghl_contact_id);
CREATE INDEX IF NOT EXISTS idx_timeline_job ON job_timeline(job_id);
CREATE INDEX IF NOT EXISTS idx_photos_job ON job_photos(job_id);
CREATE INDEX IF NOT EXISTS idx_line_items_job ON job_line_items(job_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_job ON time_entries(job_id);
CREATE INDEX IF NOT EXISTS idx_invoices_job ON invoices(job_id);

-- ─── ROW LEVEL SECURITY ─────────────────────────────────────
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE technicians ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_timeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE price_book ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_checklists ENABLE ROW LEVEL SECURITY;

-- For now, allow all authenticated users full access (tighten later per role)
CREATE POLICY "Allow all for authenticated" ON customers FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON technicians FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON jobs FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON job_line_items FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON job_photos FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON job_timeline FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON invoices FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON price_book FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON time_entries FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON checklist_templates FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Allow all for authenticated" ON job_checklists FOR ALL USING (auth.role() = 'authenticated');

-- ─── SEED PRICE BOOK ─────────────────────────────────────────
INSERT INTO price_book (service_id, name, category, price, cost, duration_minutes, sort_order) VALUES
  ('standard-clean', 'Standard Dryer Vent Cleaning', 'cleaning', 139, 25, 60, 1),
  ('deep-clean', 'Deep Clean (20+ ft run)', 'cleaning', 219, 35, 90, 2),
  ('roof-clean', 'Roof-Level Vent Cleaning', 'cleaning', 249, 40, 90, 3),
  ('inspection', 'Dryer Vent Inspection', 'inspection', 69, 10, 30, 4),
  ('bird-guard', 'Bird Guard Installation', 'install', 125, 45, 45, 5),
  ('vent-cap', 'Vent Cap Replacement', 'repair', 135, 35, 45, 6),
  ('reroute', 'Vent Re-Route (Flex to Rigid)', 'install', 500, 120, 180, 7),
  ('booster-fan', 'Booster Fan Installation', 'install', 350, 150, 120, 8),
  ('lint-alarm', 'Lint Alert Sensor Install', 'install', 89, 30, 30, 9),
  ('commercial', 'Commercial Unit Cleaning', 'cleaning', 99, 20, 30, 10),
  ('maintenance-plan', 'Annual Maintenance Plan', 'plan', 149, 25, 60, 11),
  ('emergency', 'Emergency Service Call', 'emergency', 199, 30, 60, 12)
ON CONFLICT (service_id) DO NOTHING;

-- ─── SEED CHECKLIST TEMPLATES ────────────────────────────────
INSERT INTO checklist_templates (name, service_id, items) VALUES
  ('Standard Vent Cleaning', 'standard-clean', '[
    {"label": "Confirm customer is home / access available", "required": true},
    {"label": "Locate dryer vent exterior termination", "required": true},
    {"label": "Disconnect dryer from vent", "required": true},
    {"label": "Take BEFORE photo of lint buildup", "required": true},
    {"label": "Run rotary brush through full vent length", "required": true},
    {"label": "Blow out debris with high-pressure air", "required": true},
    {"label": "Inspect vent for damage, kinks, or code violations", "required": true},
    {"label": "Check exterior flap/cap operation", "required": true},
    {"label": "Reconnect dryer and verify airflow", "required": true},
    {"label": "Take AFTER photo of clean vent", "required": true},
    {"label": "Run dryer test cycle — confirm proper exhaust", "required": true},
    {"label": "Show customer before/after and explain findings", "required": false},
    {"label": "Leave maintenance sticker with next service date", "required": false}
  ]'),
  ('Vent Re-Route', 'reroute', '[
    {"label": "Confirm customer is home / access available", "required": true},
    {"label": "Photo document existing vent path", "required": true},
    {"label": "Mark new route with measurements", "required": true},
    {"label": "Remove existing flex duct", "required": true},
    {"label": "Install rigid metal duct per IRC M1502", "required": true},
    {"label": "Seal all joints with UL-listed foil tape", "required": true},
    {"label": "Support duct per code (max 4ft spacing)", "required": true},
    {"label": "Verify max 25ft equivalent length not exceeded", "required": true},
    {"label": "Connect dryer and verify airflow", "required": true},
    {"label": "Photo document completed installation", "required": true},
    {"label": "Run test cycle — measure exhaust temp and CFM", "required": true}
  ]')
ON CONFLICT DO NOTHING;

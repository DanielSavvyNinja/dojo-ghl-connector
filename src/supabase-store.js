/**
 * Supabase Store — Local persistence & real-time sync for Dojo apps
 *
 * Stores job data, technician assignments, photos, invoices locally
 * in Supabase, then syncs to GHL via the GHL Client.
 *
 * Tables (auto-created via migrations):
 *   - jobs: Full job records with GHL opportunity_id mapping
 *   - job_line_items: Service line items per job
 *   - job_photos: Photo uploads linked to jobs
 *   - job_timeline: Audit trail / activity log
 *   - technicians: Tech roster with GHL user_id mapping
 *   - customers: Local customer cache with GHL contact_id mapping
 *   - price_book: Service catalog with pricing
 *   - invoices: Invoice records with GHL invoice_id mapping
 *   - settings: App configuration
 */

import { createClient } from '@supabase/supabase-js'

export class SupabaseStore {
  constructor(url, anonKey) {
    this.client = createClient(url, anonKey)
  }

  // ─── JOBS ──────────────────────────────────────────────────
  async getJobs(filters = {}) {
    let query = this.client.from('jobs').select('*, job_line_items(*), job_photos(*)')
    if (filters.stage) query = query.eq('stage', filters.stage)
    if (filters.techId) query = query.eq('tech_id', filters.techId)
    if (filters.dateFrom) query = query.gte('scheduled_date', filters.dateFrom)
    if (filters.dateTo) query = query.lte('scheduled_date', filters.dateTo)
    query = query.order('created_at', { ascending: false })
    const { data, error } = await query
    if (error) throw error
    return data
  }

  async getJob(jobId) {
    const { data, error } = await this.client
      .from('jobs')
      .select('*, job_line_items(*), job_photos(*), job_timeline(*)')
      .eq('id', jobId)
      .single()
    if (error) throw error
    return data
  }

  async createJob(job) {
    const { lineItems, ...jobData } = job
    const { data: newJob, error } = await this.client.from('jobs').insert(jobData).select().single()
    if (error) throw error
    if (lineItems?.length) {
      const items = lineItems.map(li => ({ ...li, job_id: newJob.id }))
      await this.client.from('job_line_items').insert(items)
    }
    return newJob
  }

  async updateJob(jobId, updates) {
    const { data, error } = await this.client.from('jobs').update(updates).eq('id', jobId).select().single()
    if (error) throw error
    return data
  }

  async updateJobStage(jobId, stage, userId = null) {
    const { data, error } = await this.client.from('jobs').update({ stage }).eq('id', jobId).select().single()
    if (error) throw error
    await this.addTimelineEvent(jobId, `Stage changed to ${stage}`, userId)
    return data
  }

  // ─── TIMELINE ──────────────────────────────────────────────
  async addTimelineEvent(jobId, action, userId = null) {
    return this.client.from('job_timeline').insert({
      job_id: jobId,
      action,
      performed_by: userId,
      created_at: new Date().toISOString(),
    })
  }

  async getTimeline(jobId) {
    const { data, error } = await this.client
      .from('job_timeline')
      .select('*')
      .eq('job_id', jobId)
      .order('created_at', { ascending: false })
    if (error) throw error
    return data
  }

  // ─── PHOTOS ────────────────────────────────────────────────
  async uploadPhoto(jobId, file, type = 'during') {
    const fileName = `${jobId}/${Date.now()}_${file.name}`
    const { data: upload, error: uploadError } = await this.client.storage
      .from('job-photos')
      .upload(fileName, file)
    if (uploadError) throw uploadError

    const { data: { publicUrl } } = this.client.storage.from('job-photos').getPublicUrl(fileName)

    return this.client.from('job_photos').insert({
      job_id: jobId,
      file_name: file.name,
      file_path: fileName,
      public_url: publicUrl,
      photo_type: type, // before, during, after
    })
  }

  // ─── CUSTOMERS ─────────────────────────────────────────────
  async getCustomers(search = '') {
    let query = this.client.from('customers').select('*')
    if (search) query = query.or(`name.ilike.%${search}%,email.ilike.%${search}%,phone.ilike.%${search}%`)
    const { data, error } = await query.order('name')
    if (error) throw error
    return data
  }

  async upsertCustomer(customer) {
    const { data, error } = await this.client.from('customers').upsert(customer, { onConflict: 'ghl_contact_id' }).select().single()
    if (error) throw error
    return data
  }

  // ─── PRICE BOOK ────────────────────────────────────────────
  async getPriceBook() {
    const { data, error } = await this.client.from('price_book').select('*').order('category', { ascending: true })
    if (error) throw error
    return data
  }

  async upsertService(service) {
    const { data, error } = await this.client.from('price_book').upsert(service).select().single()
    if (error) throw error
    return data
  }

  // ─── TECHNICIANS ───────────────────────────────────────────
  async getTechnicians() {
    const { data, error } = await this.client.from('technicians').select('*').order('name')
    if (error) throw error
    return data
  }

  // ─── INVOICES ──────────────────────────────────────────────
  async createInvoice(invoice) {
    const { data, error } = await this.client.from('invoices').insert(invoice).select().single()
    if (error) throw error
    return data
  }

  async getInvoicesForJob(jobId) {
    const { data, error } = await this.client.from('invoices').select('*').eq('job_id', jobId)
    if (error) throw error
    return data
  }

  // ─── REAL-TIME SUBSCRIPTIONS ───────────────────────────────
  subscribeToJobs(callback) {
    return this.client.channel('jobs-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'jobs' }, callback)
      .subscribe()
  }

  subscribeToTimeline(jobId, callback) {
    return this.client.channel(`timeline-${jobId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'job_timeline', filter: `job_id=eq.${jobId}` }, callback)
      .subscribe()
  }
}

export function createSupabaseStore(url, anonKey) {
  return new SupabaseStore(url, anonKey)
}

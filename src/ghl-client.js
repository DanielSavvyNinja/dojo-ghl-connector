/**
 * GHL API Client — GoHighLevel REST API v2
 * Base URL: https://services.leadconnectorhq.com
 *
 * Handles: Contacts, Opportunities, Calendars, Invoices, Workflows, Custom Fields, Notes
 * Auth: Bearer token (API key from GHL Location settings)
 */

const GHL_BASE = 'https://services.leadconnectorhq.com'

export class GHLClient {
  constructor({ apiKey, locationId, version = '2021-07-28' }) {
    this.apiKey = apiKey
    this.locationId = locationId
    this.version = version
  }

  async _request(method, path, body = null, params = {}) {
    const url = new URL(`${GHL_BASE}${path}`)
    Object.entries(params).forEach(([k, v]) => { if (v != null) url.searchParams.set(k, v) })

    const headers = {
      'Authorization': `Bearer ${this.apiKey}`,
      'Version': this.version,
      'Content-Type': 'application/json',
    }

    const res = await fetch(url.toString(), {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    })

    if (!res.ok) {
      const err = await res.text()
      throw new Error(`GHL API Error ${res.status}: ${err}`)
    }
    return res.json()
  }

  // ─── CONTACTS ──────────────────────────────────────────────
  async getContacts(query = {}) {
    return this._request('GET', '/contacts/', null, { locationId: this.locationId, ...query })
  }

  async getContact(contactId) {
    return this._request('GET', `/contacts/${contactId}`)
  }

  async createContact(data) {
    return this._request('POST', '/contacts/', { ...data, locationId: this.locationId })
  }

  async updateContact(contactId, data) {
    return this._request('PUT', `/contacts/${contactId}`, data)
  }

  async searchContacts(query) {
    return this._request('GET', '/contacts/search', null, {
      locationId: this.locationId,
      query,
    })
  }

  async addContactNote(contactId, body) {
    return this._request('POST', `/contacts/${contactId}/notes`, { body, userId: this.locationId })
  }

  async addContactTag(contactId, tags) {
    return this._request('POST', `/contacts/${contactId}/tags`, { tags })
  }

  // ─── OPPORTUNITIES (Pipeline/Jobs) ─────────────────────────
  async getOpportunities(pipelineId, query = {}) {
    return this._request('GET', '/opportunities/search', null, {
      location_id: this.locationId,
      pipeline_id: pipelineId,
      ...query,
    })
  }

  async getOpportunity(opportunityId) {
    return this._request('GET', `/opportunities/${opportunityId}`)
  }

  async createOpportunity(data) {
    return this._request('POST', '/opportunities/', {
      ...data,
      locationId: this.locationId,
    })
  }

  async updateOpportunity(opportunityId, data) {
    return this._request('PUT', `/opportunities/${opportunityId}`, data)
  }

  async updateOpportunityStatus(opportunityId, status) {
    return this._request('PUT', `/opportunities/${opportunityId}/status`, { status })
  }

  // ─── PIPELINES ─────────────────────────────────────────────
  async getPipelines() {
    return this._request('GET', '/opportunities/pipelines', null, { locationId: this.locationId })
  }

  // ─── CALENDARS ─────────────────────────────────────────────
  async getCalendars() {
    return this._request('GET', '/calendars/', null, { locationId: this.locationId })
  }

  async getCalendarEvents(calendarId, startTime, endTime) {
    return this._request('GET', '/calendars/events', null, {
      locationId: this.locationId,
      calendarId,
      startTime,
      endTime,
    })
  }

  async createCalendarEvent(calendarId, data) {
    return this._request('POST', '/calendars/events', {
      ...data,
      calendarId,
      locationId: this.locationId,
    })
  }

  async updateCalendarEvent(eventId, data) {
    return this._request('PUT', `/calendars/events/${eventId}`, data)
  }

  // ─── INVOICES ──────────────────────────────────────────────
  async createInvoice(data) {
    return this._request('POST', '/invoices/', {
      ...data,
      altId: this.locationId,
      altType: 'location',
    })
  }

  async getInvoice(invoiceId) {
    return this._request('GET', `/invoices/${invoiceId}`, null, {
      altId: this.locationId,
      altType: 'location',
    })
  }

  async sendInvoice(invoiceId) {
    return this._request('POST', `/invoices/${invoiceId}/send`)
  }

  async listInvoices(query = {}) {
    return this._request('GET', '/invoices/', null, {
      altId: this.locationId,
      altType: 'location',
      ...query,
    })
  }

  // ─── WORKFLOWS ─────────────────────────────────────────────
  async getWorkflows() {
    return this._request('GET', '/workflows/', null, { locationId: this.locationId })
  }

  // ─── CUSTOM VALUES & FIELDS ────────────────────────────────
  async getCustomFields() {
    return this._request('GET', '/locations/custom-fields', null, { locationId: this.locationId })
  }

  async getCustomValues() {
    return this._request('GET', '/locations/custom-values', null, { locationId: this.locationId })
  }

  // ─── CONVERSATIONS ─────────────────────────────────────────
  async sendSMS(contactId, message) {
    return this._request('POST', '/conversations/messages', {
      type: 'SMS',
      contactId,
      message,
    })
  }

  async sendEmail(contactId, subject, htmlBody) {
    return this._request('POST', '/conversations/messages', {
      type: 'Email',
      contactId,
      subject,
      html: htmlBody,
    })
  }

  // ─── USERS (Technicians) ──────────────────────────────────
  async getUsers() {
    return this._request('GET', '/users/', null, { locationId: this.locationId })
  }

  // ─── PAYMENTS ──────────────────────────────────────────────
  async getTransactions(query = {}) {
    return this._request('GET', '/payments/transactions', null, {
      locationId: this.locationId,
      ...query,
    })
  }
}

export function createGHLClient(config) {
  return new GHLClient(config)
}

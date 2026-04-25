/**
 * Dojo Initialization — sets up both GHL and Supabase connections
 *
 * Call once at app startup:
 *   const { ghl, store } = await initDojo()
 *
 * Config is read from environment variables:
 *   VITE_GHL_API_KEY       — GHL Location API key
 *   VITE_GHL_LOCATION_ID   — GHL Location ID (e.g., 3GI7SZRZHugGLBnDevX2)
 *   VITE_SUPABASE_URL      — Supabase project URL
 *   VITE_SUPABASE_ANON_KEY — Supabase anonymous key
 */

import { createGHLClient } from './ghl-client.js'
import { createSupabaseStore } from './supabase-store.js'

let _ghl = null
let _store = null

export async function initDojo(overrides = {}) {
  const config = {
    ghlApiKey: overrides.ghlApiKey || import.meta.env?.VITE_GHL_API_KEY || '',
    ghlLocationId: overrides.ghlLocationId || import.meta.env?.VITE_GHL_LOCATION_ID || '3GI7SZRZHugGLBnDevX2',
    supabaseUrl: overrides.supabaseUrl || import.meta.env?.VITE_SUPABASE_URL || '',
    supabaseAnonKey: overrides.supabaseAnonKey || import.meta.env?.VITE_SUPABASE_ANON_KEY || '',
  }

  // Initialize GHL client
  if (config.ghlApiKey) {
    _ghl = createGHLClient({
      apiKey: config.ghlApiKey,
      locationId: config.ghlLocationId,
    })
  } else {
    console.warn('[Dojo] No GHL API key — running in demo mode. Set VITE_GHL_API_KEY in .env')
  }

  // Initialize Supabase store
  if (config.supabaseUrl && config.supabaseAnonKey) {
    _store = createSupabaseStore(config.supabaseUrl, config.supabaseAnonKey)
  } else {
    console.warn('[Dojo] No Supabase config — running with local state only. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env')
  }

  return { ghl: _ghl, store: _store, config }
}

export function getGHL() { return _ghl }
export function getStore() { return _store }

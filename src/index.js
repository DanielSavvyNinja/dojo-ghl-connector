/**
 * Dojo GHL Connector — Shared API layer for all Dojo FS Command apps
 *
 * Connects to GoHighLevel (The Dojo whitelabel) via:
 *   - GHL REST API v2 (https://services.leadconnectorhq.com)
 *   - Supabase for local data persistence & real-time sync
 *
 * Usage:
 *   import { ghl, supabase, initDojo } from 'dojo-ghl-connector'
 *   await initDojo({ ghlApiKey: '...', locationId: '...' })
 */

export { GHLClient, createGHLClient } from './ghl-client.js'
export { SupabaseStore, createSupabaseStore } from './supabase-store.js'
export { initDojo } from './init.js'

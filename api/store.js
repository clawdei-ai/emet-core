/**
 * EMET API — SQLite Persistent Store
 *
 * Persists claims, signatures, and reputation data to SQLite.
 * Uses better-sqlite3 for fast synchronous operations.
 * 
 * This module provides backwards-compatible exports from the modular db/ layer.
 * 
 * @module @emet-protocol/api/store
 * @version 0.4.0
 */

const claims = require('./db/claims');
const reputation = require('./db/reputation');
const { getDatabase, closeDatabase, getSchemaVersion } = require('./db/index');

// Re-export all claims functions for backwards compatibility
module.exports = {
  // Claim operations
  get: claims.get,
  put: claims.put,
  list: claims.list,
  del: claims.del,
  readAll: claims.readAll,
  count: claims.count,
  
  // Database access
  getDatabase,
  closeDatabase,
  getSchemaVersion,
  
  // Sub-modules for direct access
  claims,
  reputation
};

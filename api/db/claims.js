/**
 * EMET Protocol — Claims SQLite Store
 * 
 * CRUD operations for claims with signatures and co-signatories.
 * 
 * @module @emet-protocol/api/db/claims
 * @version 0.4.0
 */

const { getDatabase } = require('./index');

/**
 * Create a claims store with the given database
 * @param {Database.Database} [database] - Optional database instance (uses default if not provided)
 * @returns {ClaimsStore}
 */
function createClaimsStore(database = null) {
  const getDb = () => database || getDatabase();
  
  return {
    /**
     * Store a claim (insert or update)
     * @param {Object} claim - The claim object
     * @returns {Object} The stored claim
     */
    put(claim) {
      const db = getDb();
      
      // Prepare content as JSON
      const content = JSON.stringify(claim.content || {
        statement: claim.statement,
        domain: claim.domain,
        scope: claim.scope,
        caveats: claim.caveats
      });
      
      const evidence = JSON.stringify(claim.evidence || []);
      
      // Upsert claim
      const stmt = db.prepare(`
        INSERT INTO claims (id, type, issuer, subject, content, evidence, confidence, timestamp, version, previous_version, thread_id, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
          type = excluded.type,
          issuer = excluded.issuer,
          subject = excluded.subject,
          content = excluded.content,
          evidence = excluded.evidence,
          confidence = excluded.confidence,
          timestamp = excluded.timestamp,
          version = excluded.version,
          previous_version = excluded.previous_version,
          thread_id = excluded.thread_id,
          updated_at = datetime('now')
      `);
      
      stmt.run(
        claim.id,
        claim.type,
        claim.issuer,
        claim.subject || null,
        content,
        evidence,
        claim.confidence,
        claim.timestamp,
        claim.version,
        claim.previousVersion || null,
        claim.threadId || null
      );
      
      // Handle primary signature
      if (claim.signature) {
        this._upsertSignature(claim.id, claim.signature, true);
      }
      
      // Handle co-signatories
      if (claim.coSignatories && claim.coSignatories.length > 0) {
        // Clear existing co-signatories and re-insert
        db.prepare('DELETE FROM co_signatories WHERE claim_id = ?').run(claim.id);
        
        for (const coSig of claim.coSignatories) {
          this._insertCoSignatory(claim.id, coSig);
        }
      }
      
      return claim;
    },
    
    /**
     * Insert or update a signature
     * @private
     */
    _upsertSignature(claimId, signature, isPrimary = true) {
      const db = getDb();
      
      // Remove existing primary signature if inserting a new one
      if (isPrimary) {
        db.prepare('DELETE FROM signatures WHERE claim_id = ? AND is_primary = 1').run(claimId);
      }
      
      const stmt = db.prepare(`
        INSERT INTO signatures (claim_id, signer, algorithm, public_key, signature, timestamp, canonicalization, hash_algorithm, is_primary)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
      
      stmt.run(
        claimId,
        signature.signer,
        signature.algorithm,
        signature.publicKey,
        signature.signature,
        signature.timestamp,
        signature.canonicalization || 'jcs',
        signature.hashAlgorithm || 'sha256',
        isPrimary ? 1 : 0
      );
    },
    
    /**
     * Insert a co-signatory
     * @private
     */
    _insertCoSignatory(claimId, coSig) {
      const db = getDb();
      
      const stmt = db.prepare(`
        INSERT INTO co_signatories (claim_id, agent, endorsement_type, signer, algorithm, public_key, signature, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `);
      
      stmt.run(
        claimId,
        coSig.agent,
        coSig.endorsementType || 'full',
        coSig.signature.signer,
        coSig.signature.algorithm,
        coSig.signature.publicKey,
        coSig.signature.signature,
        coSig.signature.timestamp
      );
    },
    
    /**
     * Get a claim by ID
     * @param {string} id - The claim ID
     * @returns {Object|null} The claim or null if not found
     */
    get(id) {
      const db = getDb();
      
      const row = db.prepare('SELECT * FROM claims WHERE id = ?').get(id);
      if (!row) return null;
      
      return this._rowToClaim(row);
    },
    
    /**
     * Convert a database row to a claim object
     * @private
     */
    _rowToClaim(row) {
      const db = getDb();
      
      const content = JSON.parse(row.content);
      const evidence = JSON.parse(row.evidence);
      
      // Get primary signature
      const sigRow = db.prepare(
        'SELECT * FROM signatures WHERE claim_id = ? AND is_primary = 1'
      ).get(row.id);
      
      // Get co-signatories
      const coSigRows = db.prepare(
        'SELECT * FROM co_signatories WHERE claim_id = ?'
      ).all(row.id);
      
      const claim = {
        id: row.id,
        type: row.type,
        issuer: row.issuer,
        content,
        evidence,
        confidence: row.confidence,
        timestamp: row.timestamp,
        version: row.version,
        coSignatories: coSigRows.map(cs => ({
          agent: cs.agent,
          endorsementType: cs.endorsement_type,
          timestamp: cs.timestamp,
          signature: {
            claimId: row.id,
            signer: cs.signer,
            algorithm: cs.algorithm,
            publicKey: cs.public_key,
            signature: cs.signature,
            timestamp: cs.timestamp
          }
        }))
      };
      
      if (row.subject) claim.subject = row.subject;
      if (row.previous_version) claim.previousVersion = row.previous_version;
      if (row.thread_id) claim.threadId = row.thread_id;
      
      // Add signature if exists
      if (sigRow) {
        claim.signature = {
          claimId: row.id,
          signer: sigRow.signer,
          algorithm: sigRow.algorithm,
          publicKey: sigRow.public_key,
          signature: sigRow.signature,
          timestamp: sigRow.timestamp,
          canonicalization: sigRow.canonicalization,
          hashAlgorithm: sigRow.hash_algorithm
        };
      }
      
      return claim;
    },
    
    /**
     * List all claims
     * @param {Object} [options] - Query options
     * @param {number} [options.limit] - Maximum number of claims to return
     * @param {number} [options.offset] - Number of claims to skip
     * @param {string} [options.issuer] - Filter by issuer
     * @param {string} [options.type] - Filter by claim type
     * @param {string} [options.orderBy='timestamp'] - Order by field
     * @param {string} [options.order='DESC'] - Order direction
     * @returns {Object[]} Array of claims
     */
    list(options = {}) {
      const db = getDb();
      
      let sql = 'SELECT * FROM claims WHERE 1=1';
      const params = [];
      
      if (options.issuer) {
        sql += ' AND issuer = ?';
        params.push(options.issuer);
      }
      
      if (options.type) {
        sql += ' AND type = ?';
        params.push(options.type);
      }
      
      const orderBy = options.orderBy || 'timestamp';
      const order = options.order === 'ASC' ? 'ASC' : 'DESC';
      sql += ` ORDER BY ${orderBy} ${order}`;
      
      if (options.limit) {
        sql += ' LIMIT ?';
        params.push(options.limit);
      }
      
      if (options.offset) {
        sql += ' OFFSET ?';
        params.push(options.offset);
      }
      
      const rows = db.prepare(sql).all(...params);
      return rows.map(row => this._rowToClaim(row));
    },
    
    /**
     * Delete a claim by ID
     * @param {string} id - The claim ID
     * @returns {boolean} True if the claim was deleted
     */
    del(id) {
      const db = getDb();
      const result = db.prepare('DELETE FROM claims WHERE id = ?').run(id);
      return result.changes > 0;
    },
    
    /**
     * Read all claims as a map (for backwards compatibility)
     * @returns {Object} Map of claim ID to claim object
     */
    readAll() {
      const claims = this.list();
      const map = {};
      for (const claim of claims) {
        map[claim.id] = claim;
      }
      return map;
    },
    
    /**
     * Get total count of claims
     * @param {Object} [filters] - Optional filters
     * @returns {number}
     */
    count(filters = {}) {
      const db = getDb();
      
      let sql = 'SELECT COUNT(*) as count FROM claims WHERE 1=1';
      const params = [];
      
      if (filters.issuer) {
        sql += ' AND issuer = ?';
        params.push(filters.issuer);
      }
      
      if (filters.type) {
        sql += ' AND type = ?';
        params.push(filters.type);
      }
      
      return db.prepare(sql).get(...params).count;
    },
    
    /**
     * Clear all claims (for testing)
     */
    clear() {
      const db = getDb();
      db.exec('DELETE FROM co_signatories');
      db.exec('DELETE FROM signatures');
      db.exec('DELETE FROM claims');
    }
  };
}

// Default singleton store
let defaultStore = null;

function getDefaultStore() {
  if (!defaultStore) {
    defaultStore = createClaimsStore();
  }
  return defaultStore;
}

// Export convenience functions that use the default store
module.exports = {
  createClaimsStore,
  get: (id) => getDefaultStore().get(id),
  put: (claim) => getDefaultStore().put(claim),
  list: (options) => getDefaultStore().list(options),
  del: (id) => getDefaultStore().del(id),
  readAll: () => getDefaultStore().readAll(),
  count: (filters) => getDefaultStore().count(filters),
  clear: () => getDefaultStore().clear()
};

/**
 * EMET Protocol — SQLite Database Layer
 * 
 * Provides persistent storage for claims, signatures, and reputation data.
 * Uses better-sqlite3 for synchronous, high-performance operations.
 * 
 * @module @emet-protocol/api/db
 * @version 0.4.0
 */

const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

// Default database path
const DEFAULT_DB_PATH = path.join(__dirname, '..', '.data', 'emet.db');

/**
 * Database connection singleton
 * @type {Database.Database|null}
 */
let db = null;

/**
 * Get or create the database connection
 * @param {string} [dbPath] - Optional path to database file
 * @returns {Database.Database}
 */
function getDatabase(dbPath = null) {
  if (db) return db;
  
  const resolvedPath = dbPath || process.env.EMET_DB_PATH || DEFAULT_DB_PATH;
  
  // Ensure directory exists
  const dir = path.dirname(resolvedPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  
  // Create database connection
  db = new Database(resolvedPath);
  
  // Enable WAL mode for better concurrent access
  db.pragma('journal_mode = WAL');
  
  // Enable foreign keys
  db.pragma('foreign_keys = ON');
  
  // Run migrations
  runMigrations(db);
  
  return db;
}

/**
 * Close the database connection
 */
function closeDatabase() {
  if (db) {
    db.close();
    db = null;
  }
}

/**
 * Get a fresh in-memory database (for testing)
 * @returns {Database.Database}
 */
function getTestDatabase() {
  const testDb = new Database(':memory:');
  testDb.pragma('foreign_keys = ON');
  runMigrations(testDb);
  return testDb;
}

/**
 * Migration definitions
 * Each migration has a version number, name, and up/down SQL
 */
const MIGRATIONS = [
  {
    version: 1,
    name: 'initial_schema',
    up: `
      -- Claims table
      CREATE TABLE IF NOT EXISTS claims (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        issuer TEXT NOT NULL,
        subject TEXT,
        content TEXT NOT NULL,
        evidence TEXT NOT NULL DEFAULT '[]',
        confidence REAL NOT NULL DEFAULT 0.5,
        timestamp TEXT NOT NULL,
        version TEXT NOT NULL DEFAULT '1.0.0',
        previous_version TEXT,
        thread_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      
      -- Signatures table
      CREATE TABLE IF NOT EXISTS signatures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        claim_id TEXT NOT NULL,
        signer TEXT NOT NULL,
        algorithm TEXT NOT NULL DEFAULT 'ed25519',
        public_key TEXT NOT NULL,
        signature TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        canonicalization TEXT DEFAULT 'jcs',
        hash_algorithm TEXT DEFAULT 'sha256',
        is_primary INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (claim_id) REFERENCES claims(id) ON DELETE CASCADE
      );
      
      -- Co-signatories table
      CREATE TABLE IF NOT EXISTS co_signatories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        claim_id TEXT NOT NULL,
        agent TEXT NOT NULL,
        endorsement_type TEXT NOT NULL DEFAULT 'full',
        signer TEXT NOT NULL,
        algorithm TEXT NOT NULL DEFAULT 'ed25519',
        public_key TEXT NOT NULL,
        signature TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (claim_id) REFERENCES claims(id) ON DELETE CASCADE
      );
      
      -- Reputation table
      CREATE TABLE IF NOT EXISTS agents (
        id TEXT PRIMARY KEY,
        score REAL NOT NULL DEFAULT 50,
        verifications INTEGER NOT NULL DEFAULT 0,
        correct_verifications INTEGER NOT NULL DEFAULT 0,
        accuracy REAL NOT NULL DEFAULT 0.5,
        last_activity INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      
      -- Agent claims (many-to-many for tracking which claims each agent made)
      CREATE TABLE IF NOT EXISTS agent_claims (
        agent_id TEXT NOT NULL,
        claim_id TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (agent_id, claim_id),
        FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE,
        FOREIGN KEY (claim_id) REFERENCES claims(id) ON DELETE CASCADE
      );
      
      -- Verification results
      CREATE TABLE IF NOT EXISTS verification_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        agent_id TEXT NOT NULL,
        claim_id TEXT NOT NULL,
        result INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE
      );
      
      -- Indexes for common queries
      CREATE INDEX IF NOT EXISTS idx_claims_issuer ON claims(issuer);
      CREATE INDEX IF NOT EXISTS idx_claims_type ON claims(type);
      CREATE INDEX IF NOT EXISTS idx_claims_thread ON claims(thread_id);
      CREATE INDEX IF NOT EXISTS idx_claims_timestamp ON claims(timestamp);
      CREATE INDEX IF NOT EXISTS idx_signatures_claim ON signatures(claim_id);
      CREATE INDEX IF NOT EXISTS idx_co_signatories_claim ON co_signatories(claim_id);
      CREATE INDEX IF NOT EXISTS idx_agents_score ON agents(score DESC);
      CREATE INDEX IF NOT EXISTS idx_agent_claims_agent ON agent_claims(agent_id);
      CREATE INDEX IF NOT EXISTS idx_verification_results_agent ON verification_results(agent_id);
      
      -- Migrations tracking table
      CREATE TABLE IF NOT EXISTS migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    `,
    down: `
      DROP TABLE IF EXISTS verification_results;
      DROP TABLE IF EXISTS agent_claims;
      DROP TABLE IF EXISTS agents;
      DROP TABLE IF EXISTS co_signatories;
      DROP TABLE IF EXISTS signatures;
      DROP TABLE IF EXISTS claims;
      DROP TABLE IF EXISTS migrations;
    `
  }
];

/**
 * Run pending migrations
 * @param {Database.Database} database
 */
function runMigrations(database) {
  // Create migrations table if not exists (bootstrapping)
  database.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  
  // Get current version
  const currentVersion = database.prepare(
    'SELECT MAX(version) as version FROM migrations'
  ).get()?.version || 0;
  
  // Run pending migrations
  for (const migration of MIGRATIONS) {
    if (migration.version > currentVersion) {
      console.log(`[EMET DB] Running migration ${migration.version}: ${migration.name}`);
      
      database.exec(migration.up);
      
      database.prepare(
        'INSERT INTO migrations (version, name) VALUES (?, ?)'
      ).run(migration.version, migration.name);
    }
  }
}

/**
 * Get the current schema version
 * @param {Database.Database} [database]
 * @returns {number}
 */
function getSchemaVersion(database = null) {
  const db = database || getDatabase();
  return db.prepare(
    'SELECT MAX(version) as version FROM migrations'
  ).get()?.version || 0;
}

/**
 * Rollback to a specific version (for testing/development)
 * @param {number} targetVersion
 * @param {Database.Database} [database]
 */
function rollbackTo(targetVersion, database = null) {
  const db = database || getDatabase();
  const currentVersion = getSchemaVersion(db);
  
  // Find migrations to rollback in reverse order
  const toRollback = MIGRATIONS
    .filter(m => m.version > targetVersion && m.version <= currentVersion)
    .sort((a, b) => b.version - a.version);
  
  for (const migration of toRollback) {
    console.log(`[EMET DB] Rolling back migration ${migration.version}: ${migration.name}`);
    db.exec(migration.down);
    db.prepare('DELETE FROM migrations WHERE version = ?').run(migration.version);
  }
}

module.exports = {
  getDatabase,
  closeDatabase,
  getTestDatabase,
  getSchemaVersion,
  rollbackTo,
  runMigrations,
  MIGRATIONS,
  DEFAULT_DB_PATH
};

/**
 * EMET API — Simple JSON File Store
 *
 * Persists claims to a local JSON file.  Good enough for dev/test;
 * swap for a real DB when you need it.
 */

const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '.data');
const CLAIMS_FILE = path.join(DATA_DIR, 'claims.json');

/** Ensure the data directory and file exist. */
function init() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
  if (!fs.existsSync(CLAIMS_FILE)) {
    fs.writeFileSync(CLAIMS_FILE, '{}');
  }
}

/** Read the entire claims map from disk. */
function readAll() {
  init();
  return JSON.parse(fs.readFileSync(CLAIMS_FILE, 'utf-8'));
}

/** Write the entire claims map to disk. */
function writeAll(data) {
  init();
  fs.writeFileSync(CLAIMS_FILE, JSON.stringify(data, null, 2));
}

/** Get a single claim by its EMET id (e.g. "emet:claim:<uuid>"). */
function get(id) {
  return readAll()[id] ?? null;
}

/** Store a claim, keyed by its id. Returns the claim. */
function put(claim) {
  const all = readAll();
  all[claim.id] = claim;
  writeAll(all);
  return claim;
}

/** Return every stored claim as an array. */
function list() {
  return Object.values(readAll());
}

/** Delete a claim by id. Returns true if it existed. */
function del(id) {
  const all = readAll();
  if (!(id in all)) return false;
  delete all[id];
  writeAll(all);
  return true;
}

module.exports = { get, put, list, del, readAll };

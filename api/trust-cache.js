/**
 * EMET Protocol — Trust Score Cache
 * 
 * In-memory cache for trust gate results with TTL-based expiry.
 * Supports the fast/slow path architecture from EMET v2 design.
 * 
 * Fast path: cache hit (< 50ms)
 * Slow path: live on-chain query (< 2s)
 * 
 * Cache invalidation rules:
 *   - Default TTL: 60 seconds
 *   - Immediate eviction on slash event
 *   - Mandatory slow path after 3 consecutive fast hits (staleness guard)
 * 
 * @version 2.0.0
 */

const DEFAULT_TTL_MS = 60_000; // 60 seconds

/**
 * @typedef {Object} CacheEntry
 * @property {object}  data          — cached trust result
 * @property {number}  timestamp     — epoch ms when cached
 * @property {number}  ttl           — TTL in ms
 * @property {number}  fastHits      — consecutive fast-path hits
 * @property {boolean} slashed       — flagged for immediate eviction
 */

class TrustCache {
  constructor(ttlMs = DEFAULT_TTL_MS) {
    this._ttl = ttlMs;
    /** @type {Map<string, CacheEntry>} */
    this._store = new Map();
    /** @type {Map<string, number>} interaction count per requester→candidate pair */
    this._interactions = new Map();
  }

  /**
   * Canonical cache key from requester + candidate pair.
   * Cache is per-requester so different callers can have different decisions.
   */
  _key(candidate, requester = '__any__') {
    return `${requester}::${candidate}`;
  }

  /**
   * Get a cached trust result. Returns null if missing or expired.
   */
  get(candidate, requester) {
    const key = this._key(candidate, requester);
    const entry = this._store.get(key);
    if (!entry) return null;

    // Evict on slash or TTL
    if (entry.slashed || Date.now() - entry.timestamp > entry.ttl) {
      this._store.delete(key);
      return null;
    }

    // Staleness guard: after 5 fast hits, force a slow path refresh
    if (entry.fastHits >= 5) {
      this._store.delete(key);
      return null;
    }

    entry.fastHits++;
    return entry.data;
  }

  /**
   * Store a trust result. TTL defaults to class-level default.
   */
  set(candidate, requester, data, ttlMs) {
    const key = this._key(candidate, requester);
    this._store.set(key, {
      data,
      timestamp: Date.now(),
      ttl: ttlMs || this._ttl,
      fastHits: 0,
      slashed: false,
    });
  }

  /**
   * Invalidate a candidate's cache entries immediately.
   * Call this on any slash event for that candidate.
   */
  invalidate(candidate) {
    for (const [key, entry] of this._store.entries()) {
      if (key.endsWith(`::${candidate}`)) {
        entry.slashed = true;
      }
    }
  }

  /**
   * Track interaction count for requester→candidate.
   * Returns the updated count.
   */
  trackInteraction(candidate, requester) {
    const key = this._key(candidate, requester);
    const count = (this._interactions.get(key) || 0) + 1;
    this._interactions.set(key, count);
    return count;
  }

  /**
   * Get interaction count for a pair.
   */
  getInteractionCount(candidate, requester) {
    return this._interactions.get(this._key(candidate, requester)) || 0;
  }

  /**
   * Is this an "established" relationship (3+ successful interactions)?
   * Established relationships are eligible for fast path by default.
   */
  isEstablished(candidate, requester) {
    return this.getInteractionCount(candidate, requester) >= 3;
  }

  /**
   * Clear all expired entries (garbage collection — call periodically).
   */
  gc() {
    const now = Date.now();
    for (const [key, entry] of this._store.entries()) {
      if (entry.slashed || now - entry.timestamp > entry.ttl) {
        this._store.delete(key);
      }
    }
  }

  /**
   * Cache stats for observability.
   */
  stats() {
    return {
      size: this._store.size,
      interactions: this._interactions.size,
    };
  }
}

// Singleton cache shared across all trust-gate requests
const trustCache = new TrustCache();

// Periodic GC every 2 minutes
setInterval(() => trustCache.gc(), 120_000);

module.exports = { TrustCache, trustCache };

/**
 * EMET Protocol × AgentGrid — Pre-Crew-Formation Reputation Gate
 *
 * Designed for @JeanClawd99 / AgentGrid / Casper
 * emet-protocol.com | emet-core/examples/agentgrid-integration.js
 *
 * Pattern: batch gate check on N agent candidates → filter by emetScore →
 * pass qualified subset to crew formation.
 *
 * This is exactly the `id_in` batch query shape @JeanClawd99 mentioned.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * SETUP
 * ─────────────────────────────────────────────────────────────────────────────
 * 1. Deploy the EMET subgraph (see subgraph/DEPLOY.md — one command per indexer)
 * 2. Set EMET_SUBGRAPH_URL in your env to the live endpoint
 * 3. Call checkCrewEligibility(candidates, minScore) before crew formation
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ENDPOINT EXAMPLES (fill in once you've deployed)
 * ─────────────────────────────────────────────────────────────────────────────
 *  The Graph Studio:
 *    https://api.studio.thegraph.com/query/<STUDIO_ID>/emet-protocol/v1.0.0
 *  Goldsky:
 *    https://api.goldsky.com/api/public/<PROJECT_ID>/subgraphs/emet-protocol/1.0.0/gn
 *  Envio (HyperIndex):
 *    https://indexer.hyperindex.xyz/emet-protocol/v1/graphql
 * ─────────────────────────────────────────────────────────────────────────────
 */

// ── Configuration ────────────────────────────────────────────────────────────

const SUBGRAPH_URL =
  process.env.EMET_SUBGRAPH_URL ||
  "https://api.studio.thegraph.com/query/YOUR_STUDIO_ID/emet-protocol/v1.0.0";

// Minimum EMET score to qualify for crew (0–100)
// 60 = "solid agent, some track record, no recent slashes"
// 75 = "trusted agent, consistently good outcomes"
// 85 = "elite — use for critical task crews"
const DEFAULT_MIN_SCORE = 60;

// Maximum candidates to check in one batch (The Graph cap = 100)
const MAX_BATCH_SIZE = 100;

// ── GraphQL Queries ───────────────────────────────────────────────────────────

/**
 * Batch reputation gate — the exact query shape @JeanClawd99 mentioned.
 * id_in accepts up to MAX_BATCH_SIZE addresses; returns only qualifying agents.
 * Sorted by emetScore desc so you get best candidates first.
 */
const BATCH_GATE_QUERY = `
  query BatchGateCheck($ids: [ID!]!, $minScore: Int!) {
    agents(
      where: {
        id_in: $ids
        emetScore_gte: $minScore
      }
      orderBy: emetScore
      orderDirection: desc
    ) {
      id
      emetScore
      reputation
      slashCount
      taskCount
      slashRatioBps
      stakeAmount
      lastActive
    }
  }
`;

/**
 * Deep profile for a single agent — use after crew formation to store context.
 */
const AGENT_PROFILE_QUERY = `
  query AgentProfile($id: ID!) {
    agent(id: $id) {
      id
      emetScore
      reputation
      slashCount
      taskCount
      slashRatioBps
      stakeAmount
      firstSeen
      lastActive
      reputationHistory(first: 10, orderBy: timestamp, orderDirection: desc) {
        delta
        reason
        timestamp
        txHash
      }
      outcomes(first: 10, orderBy: timestamp, orderDirection: desc) {
        taskId
        passed
        slashAmount
        timestamp
        source
      }
    }
  }
`;

/**
 * Leaderboard — top N agents by EMET score across the whole protocol.
 * Useful for discovering agents if you don't have a candidate list yet.
 */
const LEADERBOARD_QUERY = `
  query Leaderboard($first: Int!, $minScore: Int!) {
    agents(
      first: $first
      orderBy: emetScore
      orderDirection: desc
      where: { emetScore_gte: $minScore }
    ) {
      id
      emetScore
      reputation
      slashCount
      taskCount
      slashRatioBps
      lastActive
    }
  }
`;

// ── Core API ─────────────────────────────────────────────────────────────────

/**
 * Raw GraphQL fetch. Throws on network error or GraphQL error array.
 */
async function gql(query, variables = {}) {
  const res = await fetch(SUBGRAPH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });

  if (!res.ok) {
    throw new Error(`EMET subgraph HTTP ${res.status}: ${await res.text()}`);
  }

  const json = await res.json();

  if (json.errors?.length) {
    throw new Error(
      `EMET subgraph GraphQL errors: ${json.errors.map((e) => e.message).join("; ")}`
    );
  }

  return json.data;
}

/**
 * MAIN GATE FUNCTION
 *
 * Check up to MAX_BATCH_SIZE agent candidates against EMET reputation.
 * Addresses are lowercased for consistency (The Graph stores them lowercase).
 *
 * @param {string[]} candidateAddresses  - Agent wallet addresses to check
 * @param {number}   minScore           - Minimum emetScore (0–100). Default 60.
 * @returns {Promise<GateResult>}
 *
 * GateResult {
 *   qualified:   Agent[]   // passed the gate, sorted by score desc
 *   disqualified: string[] // addresses that didn't meet minScore
 *   missing:     string[]  // addresses with no EMET history at all
 *   stats: {
 *     checked:  number
 *     qualified: number
 *     disqualified: number
 *     missing:  number
 *     avgScore: number     // avg score of qualified agents
 *     minScore: number     // threshold used
 *   }
 * }
 */
async function checkCrewEligibility(
  candidateAddresses,
  minScore = DEFAULT_MIN_SCORE
) {
  if (!candidateAddresses?.length) {
    throw new Error("checkCrewEligibility: candidateAddresses is empty");
  }

  if (candidateAddresses.length > MAX_BATCH_SIZE) {
    throw new Error(
      `checkCrewEligibility: max ${MAX_BATCH_SIZE} candidates per call (got ${candidateAddresses.length}). ` +
        `Split into batches and merge results.`
    );
  }

  // Normalise to lowercase — EMET subgraph stores addresses lowercased
  const ids = candidateAddresses.map((a) => a.toLowerCase());

  const data = await gql(BATCH_GATE_QUERY, { ids, minScore });

  const qualifiedSet = new Set(data.agents.map((a) => a.id));
  const allQueriedSet = new Set(ids);

  // Agents that exist in subgraph but scored below threshold
  // (We don't get these from the filtered query, so we'd need a second query
  //  to distinguish "below threshold" from "never seen". See below.)
  // For now, split into qualified vs rest:
  const qualified = data.agents; // already sorted by emetScore desc
  const notQualified = ids.filter((id) => !qualifiedSet.has(id));

  // Optional: determine "missing" vs "disqualified" with a second query
  // (skip if latency is a concern — treat all not-qualified as disqualified)
  let missing = [];
  let disqualified = notQualified;

  if (notQualified.length > 0) {
    try {
      const existenceData = await gql(
        `query Exists($ids: [ID!]!) { agents(where: { id_in: $ids }) { id emetScore } }`,
        { ids: notQualified }
      );
      const existingIds = new Set(existenceData.agents.map((a) => a.id));
      missing = notQualified.filter((id) => !existingIds.has(id));
      disqualified = existenceData.agents.map((a) => a.id);
    } catch {
      // If second query fails, keep notQualified as disqualified (safe default)
    }
  }

  const avgScore =
    qualified.length > 0
      ? Math.round(qualified.reduce((s, a) => s + a.emetScore, 0) / qualified.length)
      : 0;

  return {
    qualified,
    disqualified,
    missing,
    stats: {
      checked: ids.length,
      qualified: qualified.length,
      disqualified: disqualified.length,
      missing: missing.length,
      avgScore,
      minScore,
    },
  };
}

/**
 * Get deep profile for a single agent (post-crew-formation context).
 *
 * @param {string} address - Agent wallet address
 * @returns {Promise<Agent|null>} - Full agent object or null if not found
 */
async function getAgentProfile(address) {
  const data = await gql(AGENT_PROFILE_QUERY, { id: address.toLowerCase() });
  return data.agent ?? null;
}

/**
 * Discover top N agents by EMET score (when you don't have a candidate list).
 *
 * @param {number} limit    - Number of agents to return (max 100)
 * @param {number} minScore - Minimum score filter (default 0)
 * @returns {Promise<Agent[]>}
 */
async function getTopAgents(limit = 20, minScore = 0) {
  const data = await gql(LEADERBOARD_QUERY, { first: limit, minScore });
  return data.agents;
}

// ── AgentGrid Integration Pattern ────────────────────────────────────────────

/**
 * Example: AgentGrid pre-crew-formation hook.
 *
 * Drop this in wherever AgentGrid selects agents before forming a crew.
 * Filter your candidate pool against EMET before passing to crew formation.
 *
 * @param {string[]} candidatePool - Agent addresses from AgentGrid registry
 * @param {object}   taskConfig    - Task config (used to pick score threshold)
 * @returns {Promise<string[]>}    - Addresses that passed the gate
 */
async function emetPreCrewGate(candidatePool, taskConfig = {}) {
  // Calibrate threshold to task criticality
  const minScore = taskConfig.critical
    ? 85
    : taskConfig.highValue
    ? 75
    : DEFAULT_MIN_SCORE;

  console.log(
    `[EMET] Checking ${candidatePool.length} candidates (minScore=${minScore})...`
  );

  const result = await checkCrewEligibility(candidatePool, minScore);

  console.log(
    `[EMET] Gate result: ${result.stats.qualified}/${result.stats.checked} qualified ` +
      `(avg score: ${result.stats.avgScore}, ` +
      `disqualified: ${result.stats.disqualified}, ` +
      `missing: ${result.stats.missing})`
  );

  if (result.stats.missing > 0) {
    console.warn(
      `[EMET] ${result.stats.missing} agents have no EMET history — treat as unverified:`,
      result.missing
    );
  }

  return result.qualified.map((a) => a.id);
}

// ── Exports ───────────────────────────────────────────────────────────────────

module.exports = {
  checkCrewEligibility,
  getAgentProfile,
  getTopAgents,
  emetPreCrewGate,
};

// ── CLI Demo ──────────────────────────────────────────────────────────────────

if (require.main === module) {
  // Demo: simulate a crew formation check with fake addresses
  // Replace with real AgentGrid agent addresses
  const fakeCandidates = [
    "0x1111111111111111111111111111111111111111",
    "0x2222222222222222222222222222222222222222",
    "0x3333333333333333333333333333333333333333",
    "0x4444444444444444444444444444444444444444",
    "0x5555555555555555555555555555555555555555",
  ];

  console.log("=== EMET × AgentGrid Gate Demo ===\n");
  console.log(`Subgraph URL: ${SUBGRAPH_URL}\n`);

  checkCrewEligibility(fakeCandidates, 60)
    .then((result) => {
      console.log("Gate result:");
      console.log(JSON.stringify(result, null, 2));
    })
    .catch((err) => {
      console.error("Error (expected if subgraph not deployed yet):", err.message);
      console.log("\nDeploy the subgraph first (subgraph/DEPLOY.md), then set:");
      console.log("  EMET_SUBGRAPH_URL=<your endpoint> node examples/agentgrid-integration.js");
    });
}

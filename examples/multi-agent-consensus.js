#!/usr/bin/env node
/**
 * EMET Integration Example 2: Multi-Agent Consensus
 *
 * Problem: One AI agent's output can be wrong, hallucinated, or biased.
 * You need multiple agents to cross-check each other — but how do you
 * record that consensus in a verifiable, tamper-proof way?
 *
 * Solution: Primary agent creates a claim. Validator agents co-sign it.
 * The more co-signatories, the higher the trust weight. Challenge
 * any claim by staking tokens on-chain.
 *
 * Run: EMET_API=http://localhost:3141 node examples/multi-agent-consensus.js
 */

const EMET_API = process.env.EMET_API || 'http://localhost:3141';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------
async function post(path, body) {
  const res = await fetch(`${EMET_API}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`EMET ${path} failed: ${res.status} ${await res.text()}`);
  return res.json();
}

async function get(path) {
  const res = await fetch(`${EMET_API}${path}`);
  if (!res.ok) throw new Error(`EMET ${path} failed: ${res.status}`);
  return res.json();
}

// ---------------------------------------------------------------------------
// Agents (in production these would be separate processes/services)
// ---------------------------------------------------------------------------
const AGENTS = {
  primary: 'emet:agent:gpt-4o-primary',
  validator1: 'emet:agent:claude-validator',
  validator2: 'emet:agent:gemini-validator',
};

// ---------------------------------------------------------------------------
// Step 1: Primary agent makes a claim
// ---------------------------------------------------------------------------
async function primaryAgentClaim(statement, domain, confidence) {
  console.log(`\n[${AGENTS.primary}] Submitting claim...`);
  const claim = await post('/claims', {
    issuer: AGENTS.primary,
    statement,
    domain,
    confidence,
    caveats: ['Single-agent inference, pending validator consensus'],
  });
  console.log(`  ✓ Claim ID: ${claim.id}`);
  console.log(`  ✓ Initial confidence: ${confidence}`);
  return claim;
}

// ---------------------------------------------------------------------------
// Step 2: Validator agents co-sign (endorse or partially endorse)
// ---------------------------------------------------------------------------
async function validatorCoSign(claimId, validatorId, endorsementType, confidence) {
  console.log(`\n[${validatorId}] Co-signing claim ${claimId.slice(0, 8)}...`);
  const updated = await post(`/claims/${claimId}/sign`, {
    signer: validatorId,
    endorsementType, // 'full' | 'partial' | 'conditional'
    confidence,
  });
  const coSig = updated.coSignatories?.find(c => c.agent === validatorId);
  console.log(`  ✓ Endorsement: ${endorsementType} (confidence: ${confidence})`);
  return updated;
}

// ---------------------------------------------------------------------------
// Step 3: Check the consensus result
// ---------------------------------------------------------------------------
function computeConsensus(claim) {
  const coSigs = claim.coSignatories || [];
  if (coSigs.length === 0) return { consensus: 'none', weight: 0 };

  const fullEndorsements = coSigs.filter(c => c.endorsementType === 'full').length;
  const partialEndorsements = coSigs.filter(c => c.endorsementType === 'partial').length;
  const weight = (fullEndorsements * 1.0 + partialEndorsements * 0.5) / (coSigs.length || 1);

  return {
    consensus: weight >= 0.8 ? 'strong' : weight >= 0.5 ? 'weak' : 'contested',
    weight: weight.toFixed(2),
    fullEndorsements,
    partialEndorsements,
    validators: coSigs.length,
  };
}

// ---------------------------------------------------------------------------
// Run demo
// ---------------------------------------------------------------------------
async function demo() {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`EMET Multi-Agent Consensus Demo`);
  console.log(`API: ${EMET_API}`);
  console.log(`${'='.repeat(60)}`);

  // Primary agent makes a research claim
  const claim = await primaryAgentClaim(
    'The Fermi paradox is best explained by the Great Filter hypothesis, ' +
    'specifically that civilizations self-destruct before achieving interstellar travel.',
    'science-research',
    0.65 // single agent, moderate confidence
  );

  // Validator 1: Full endorsement — agrees with the reasoning
  let updated = await validatorCoSign(claim.id, AGENTS.validator1, 'full', 0.70);

  // Validator 2: Partial endorsement — agrees with data, not the conclusion
  updated = await validatorCoSign(claim.id, AGENTS.validator2, 'partial', 0.45);

  // Compute consensus
  const consensus = computeConsensus(updated);

  console.log(`\n${'='.repeat(60)}`);
  console.log(`Consensus Result:`);
  console.log(`  Status:     ${consensus.consensus.toUpperCase()}`);
  console.log(`  Weight:     ${consensus.weight}`);
  console.log(`  Validators: ${consensus.validators} (${consensus.fullEndorsements} full, ${consensus.partialEndorsements} partial)`);
  console.log(`  View claim: ${EMET_API}/claims/${claim.id}`);
  console.log(`${'='.repeat(60)}\n`);

  // Show what a consumer of this claim should do with the result:
  if (consensus.consensus === 'strong') {
    console.log(`ACTION: Claim is strongly endorsed. Safe to present to users as verified.`);
  } else if (consensus.consensus === 'weak') {
    console.log(`ACTION: Weak consensus. Present with caveats, seek additional validators.`);
  } else {
    console.log(`ACTION: Contested claim. Block until resolved or escalate to human review.`);
  }
}

// ---------------------------------------------------------------------------
// Quickstart with curl
// ---------------------------------------------------------------------------
/*
# 1. Create a claim
CLAIM_ID=$(curl -sX POST http://localhost:3141/claims \
  -H "Content-Type: application/json" \
  -d '{"issuer":"emet:agent:gpt-4","statement":"The patient has viral pharyngitis","domain":"medical","confidence":0.72}' \
  | jq -r '.id')

# 2. Validator co-signs
curl -X POST "http://localhost:3141/claims/$CLAIM_ID/sign" \
  -H "Content-Type: application/json" \
  -d '{"signer":"emet:agent:claude","endorsementType":"full","confidence":0.78}'

# 3. View the co-signed claim
curl "http://localhost:3141/claims/$CLAIM_ID"

# 4. Check leaderboard — who are the most trusted validators?
curl http://localhost:3141/leaderboard
*/

demo().catch(console.error);

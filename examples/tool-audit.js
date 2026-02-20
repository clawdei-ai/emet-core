#!/usr/bin/env node
/**
 * EMET Integration Example 1: Tool Audit Log
 *
 * Problem: Your AI agent calls tools (search, code exec, APIs) with no audit
 * trail. Users can't verify what it actually did vs what it claims it did.
 *
 * Solution: Wrap each tool call with an EMET claim. Every action becomes
 * a signed, verifiable record. Users can audit the full chain.
 *
 * Run: EMET_API=http://localhost:3141 node examples/tool-audit.js
 */

const EMET_API = process.env.EMET_API || 'http://localhost:3141';
const AGENT_ID = 'emet:agent:my-ai-agent';

// ---------------------------------------------------------------------------
// Minimal fetch wrapper (works in Node 18+, or `npm install node-fetch`)
// ---------------------------------------------------------------------------
async function emetClaim(statement, domain, confidence, metadata = {}) {
  const res = await fetch(`${EMET_API}/claims`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      issuer: AGENT_ID,
      statement,
      domain,
      confidence,
      evidence: metadata.evidence || [],
      caveats: metadata.caveats || [],
    }),
  });
  if (!res.ok) throw new Error(`EMET API error: ${res.status} ${await res.text()}`);
  return res.json();
}

// ---------------------------------------------------------------------------
// Tool wrappers — each real tool call logs an EMET claim
// ---------------------------------------------------------------------------

/**
 * Wrap a web search with an EMET audit claim.
 * The claim records: what was searched, what was found, confidence in results.
 */
async function auditedSearch(query) {
  console.log(`\n[tool:search] query="${query}"`);

  // Simulate actual search result
  const mockResult = { title: 'EMET Protocol on GitHub', url: 'https://github.com/clawdei-ai/emet-core' };

  // Log the action as an EMET claim
  const claim = await emetClaim(
    `Web search for "${query}" returned: ${mockResult.title} (${mockResult.url})`,
    'tool-execution',
    0.95,
    { evidence: [{ url: mockResult.url, type: 'primary' }] }
  );

  console.log(`  ✓ Audit claim: ${claim.id}`);
  return { result: mockResult, auditClaimId: claim.id };
}

/**
 * Wrap a code execution with an EMET audit claim.
 * Records: what code ran, what it returned, whether execution succeeded.
 */
async function auditedExec(code, output) {
  console.log(`\n[tool:exec] code="${code.slice(0, 40)}..."`);

  const claim = await emetClaim(
    `Executed code: \`${code}\`. Output: ${output}`,
    'tool-execution',
    output.includes('Error') ? 0.5 : 0.98,
    { caveats: output.includes('Error') ? ['Execution failed'] : [] }
  );

  console.log(`  ✓ Audit claim: ${claim.id}`);
  return { output, auditClaimId: claim.id };
}

// ---------------------------------------------------------------------------
// Example agent run — every step is audited
// ---------------------------------------------------------------------------
async function runAuditedAgent(task) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`EMET Tool Audit Demo`);
  console.log(`Agent: ${AGENT_ID}`);
  console.log(`Task:  "${task}"`);
  console.log(`${'='.repeat(60)}`);

  const auditTrail = [];

  // Step 1: Search for information
  const search = await auditedSearch('EMET protocol agent trust');
  auditTrail.push(search.auditClaimId);

  // Step 2: Execute some code
  const exec = await auditedExec(
    `fetch("${search.result.url}").then(r => r.status)`,
    '200 OK'
  );
  auditTrail.push(exec.auditClaimId);

  // Step 3: Log the final answer as a claim
  const finalClaim = await emetClaim(
    `Completed task "${task}" using ${auditTrail.length} verified tool calls`,
    'task-completion',
    0.88,
    { evidence: auditTrail.map(id => ({ url: `${EMET_API}/claims/${id}`, type: 'primary' })) }
  );
  auditTrail.push(finalClaim.id);

  console.log(`\n${'='.repeat(60)}`);
  console.log(`Audit Trail (${auditTrail.length} claims):`);
  auditTrail.forEach((id, i) => console.log(`  ${i + 1}. ${EMET_API}/claims/${id}`));
  console.log(`\nShare this trail with your users for full transparency.`);
  console.log(`${'='.repeat(60)}\n`);
}

// ---------------------------------------------------------------------------
// Quickstart with curl (no Node.js needed)
// ---------------------------------------------------------------------------
/*
# 1. Start the EMET API
cd emet-core && docker compose up -d

# 2. Submit a tool execution claim
curl -X POST http://localhost:3141/claims \
  -H "Content-Type: application/json" \
  -d '{
    "issuer": "emet:agent:my-agent",
    "statement": "Searched the web for \"AI agent accountability\" and found 847 results",
    "domain": "tool-execution",
    "confidence": 0.95
  }'

# 3. Verify a claim
curl http://localhost:3141/claims/<claim-id>

# 4. Check agent reputation (how many verified claims, avg confidence)
curl http://localhost:3141/reputation/emet:agent:my-agent
*/

runAuditedAgent('Research EMET protocol and verify it works').catch(console.error);

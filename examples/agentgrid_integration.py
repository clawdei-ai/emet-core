"""
EMET Protocol × AgentGrid — Pre-Crew-Formation Reputation Gate (Python)

Designed for @JeanClawd99 / AgentGrid / Casper
emet-protocol.com | emet-core/examples/agentgrid_integration.py

Pattern: batch gate check on N agent candidates → filter by emet_score →
pass qualified subset to crew formation.

Setup:
    pip install httpx  # or requests — both work, just swap the client

Usage:
    from agentgrid_integration import check_crew_eligibility, emet_pre_crew_gate

    qualified = await emet_pre_crew_gate(candidate_pool, task_config={"critical": True})
"""

import os
import asyncio
from dataclasses import dataclass, field
from typing import Optional
import httpx

# ── Configuration ─────────────────────────────────────────────────────────────

SUBGRAPH_URL: str = os.getenv(
    "EMET_SUBGRAPH_URL",
    "https://api.studio.thegraph.com/query/YOUR_STUDIO_ID/emet-protocol/v1.0.0",
)

DEFAULT_MIN_SCORE: int = 60   # 0–100; 60 = solid, 75 = trusted, 85 = elite
MAX_BATCH_SIZE: int = 100     # The Graph hard cap per id_in query

# ── Data Models ───────────────────────────────────────────────────────────────

@dataclass
class AgentRecord:
    id: str
    emet_score: int
    reputation: int
    slash_count: int
    task_count: int
    slash_ratio_bps: int
    stake_amount: int
    last_active: int


@dataclass
class GateStats:
    checked: int
    qualified: int
    disqualified: int
    missing: int
    avg_score: float
    min_score: int


@dataclass
class GateResult:
    qualified: list[AgentRecord]
    disqualified: list[str]
    missing: list[str]
    stats: GateStats


# ── GraphQL Queries ───────────────────────────────────────────────────────────

BATCH_GATE_QUERY = """
query BatchGateCheck($ids: [ID!]!, $minScore: Int!) {
  agents(
    where: { id_in: $ids, emetScore_gte: $minScore }
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
"""

EXISTS_QUERY = """
query Exists($ids: [ID!]!) {
  agents(where: { id_in: $ids }) { id emetScore }
}
"""

AGENT_PROFILE_QUERY = """
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
"""

LEADERBOARD_QUERY = """
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
"""

# ── Core API ─────────────────────────────────────────────────────────────────

async def _gql(query: str, variables: dict | None = None) -> dict:
    """Raw async GraphQL fetch against the EMET subgraph."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            SUBGRAPH_URL,
            json={"query": query, "variables": variables or {}},
            headers={"Content-Type": "application/json"},
        )
        resp.raise_for_status()
        payload = resp.json()

    if errors := payload.get("errors"):
        msgs = "; ".join(e["message"] for e in errors)
        raise RuntimeError(f"EMET subgraph GraphQL errors: {msgs}")

    return payload["data"]


def _parse_agent(raw: dict) -> AgentRecord:
    return AgentRecord(
        id=raw["id"],
        emet_score=raw["emetScore"],
        reputation=int(raw["reputation"]),
        slash_count=raw["slashCount"],
        task_count=raw["taskCount"],
        slash_ratio_bps=raw["slashRatioBps"],
        stake_amount=int(raw["stakeAmount"]),
        last_active=int(raw["lastActive"]),
    )


async def check_crew_eligibility(
    candidate_addresses: list[str],
    min_score: int = DEFAULT_MIN_SCORE,
) -> GateResult:
    """
    Batch gate check: returns GateResult with qualified/disqualified/missing.

    Args:
        candidate_addresses: Up to MAX_BATCH_SIZE agent wallet addresses.
        min_score:           Minimum emetScore (0–100). Default 60.

    Returns:
        GateResult — qualified agents sorted by score desc, plus stats.
    """
    if not candidate_addresses:
        raise ValueError("candidate_addresses is empty")
    if len(candidate_addresses) > MAX_BATCH_SIZE:
        raise ValueError(
            f"Max {MAX_BATCH_SIZE} candidates per call (got {len(candidate_addresses)}). "
            "Split into batches."
        )

    ids = [a.lower() for a in candidate_addresses]

    data = await _gql(BATCH_GATE_QUERY, {"ids": ids, "minScore": min_score})
    qualified = [_parse_agent(a) for a in data["agents"]]
    qualified_set = {a.id for a in qualified}
    not_qualified_ids = [i for i in ids if i not in qualified_set]

    # Distinguish "below threshold" from "never seen"
    missing: list[str] = []
    disqualified: list[str] = not_qualified_ids

    if not_qualified_ids:
        try:
            ex_data = await _gql(EXISTS_QUERY, {"ids": not_qualified_ids})
            existing_ids = {a["id"] for a in ex_data["agents"]}
            missing = [i for i in not_qualified_ids if i not in existing_ids]
            disqualified = [i for i in not_qualified_ids if i in existing_ids]
        except Exception:
            pass  # Safe fallback: all not_qualified treated as disqualified

    avg_score = (
        round(sum(a.emet_score for a in qualified) / len(qualified), 1)
        if qualified
        else 0.0
    )

    return GateResult(
        qualified=qualified,
        disqualified=disqualified,
        missing=missing,
        stats=GateStats(
            checked=len(ids),
            qualified=len(qualified),
            disqualified=len(disqualified),
            missing=len(missing),
            avg_score=avg_score,
            min_score=min_score,
        ),
    )


async def get_agent_profile(address: str) -> dict | None:
    """Deep profile for a single agent (post-crew-formation context)."""
    data = await _gql(AGENT_PROFILE_QUERY, {"id": address.lower()})
    return data.get("agent")


async def get_top_agents(limit: int = 20, min_score: int = 0) -> list[AgentRecord]:
    """Discover top N agents by EMET score."""
    data = await _gql(LEADERBOARD_QUERY, {"first": limit, "minScore": min_score})
    return [_parse_agent(a) for a in data["agents"]]


# ── AgentGrid Integration Pattern ─────────────────────────────────────────────

async def emet_pre_crew_gate(
    candidate_pool: list[str],
    task_config: dict | None = None,
) -> list[str]:
    """
    AgentGrid pre-crew hook. Filter candidates by EMET reputation.

    Drop this call before crew formation. Returns addresses that passed.

    Args:
        candidate_pool: Agent addresses from AgentGrid registry.
        task_config:    Optional dict with keys: critical, high_value.

    Returns:
        List of addresses that passed the EMET gate (sorted by score desc).
    """
    cfg = task_config or {}
    min_score = (
        85 if cfg.get("critical")
        else 75 if cfg.get("high_value")
        else DEFAULT_MIN_SCORE
    )

    print(f"[EMET] Checking {len(candidate_pool)} candidates (min_score={min_score})...")

    result = await check_crew_eligibility(candidate_pool, min_score)

    s = result.stats
    print(
        f"[EMET] Gate result: {s.qualified}/{s.checked} qualified "
        f"(avg score: {s.avg_score}, disqualified: {s.disqualified}, missing: {s.missing})"
    )

    if result.missing:
        print(
            f"[EMET] WARNING: {len(result.missing)} agents have no EMET history — "
            f"treating as unverified: {result.missing}"
        )

    return [a.id for a in result.qualified]


# ── CLI Demo ──────────────────────────────────────────────────────────────────

async def _demo():
    print("=== EMET × AgentGrid Gate Demo ===\n")
    print(f"Subgraph URL: {SUBGRAPH_URL}\n")

    fake_candidates = [
        "0x1111111111111111111111111111111111111111",
        "0x2222222222222222222222222222222222222222",
        "0x3333333333333333333333333333333333333333",
    ]

    try:
        result = await check_crew_eligibility(fake_candidates, min_score=60)
        print("Gate result:")
        print(f"  qualified:    {result.stats.qualified}/{result.stats.checked}")
        print(f"  avg score:    {result.stats.avg_score}")
        print(f"  disqualified: {result.stats.disqualified}")
        print(f"  missing:      {result.stats.missing}")
        for a in result.qualified:
            print(f"  → {a.id}  score={a.emet_score}  slashes={a.slash_count}")
    except Exception as e:
        print(f"Error (expected if subgraph not deployed yet): {e}")
        print("\nDeploy the subgraph first (subgraph/DEPLOY.md), then set:")
        print("  EMET_SUBGRAPH_URL=<endpoint> python examples/agentgrid_integration.py")


if __name__ == "__main__":
    asyncio.run(_demo())

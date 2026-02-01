import { useClaimCount } from '../hooks/useProtocol';
import { useReadContract } from 'wagmi';
import { CONTRACTS } from '../contracts/addresses';
import { EMETStakeABI } from '../contracts/abis';
import { formatEMET } from '../lib/format';

const CONCENTRATION_CAP = 5; // 5% max per staker

export function Concentration() {
  const { data: claimCount } = useClaimCount();
  const total = claimCount !== undefined ? Number(claimCount) : 0;

  // Read stake totals for each claim to compute real pool size
  const claimIds = Array.from({ length: total }, (_, i) => i);

  return (
    <div className="page">
      <h1>Concentration Dashboard</h1>
      <p className="page-subtitle">Monitor staking concentration and model family distribution across the EMET Protocol.</p>

      {/* Summary Stats */}
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-label">Total Claims</div>
          <div className="stat-value">{total}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Concentration Cap</div>
          <div className="stat-value">{CONCENTRATION_CAP}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Contracts Deployed</div>
          <div className="stat-value">16</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Tests Passing</div>
          <div className="stat-value">401</div>
        </div>
      </div>

      {/* Active Stakes */}
      <div className="card">
        <h3>Active Stakes by Claim</h3>
        {total === 0 ? (
          <p className="empty-state">No claims yet. Submit a claim to start.</p>
        ) : (
          <div className="concentration-table">
            <div className="conc-header">
              <span className="conc-rank">#</span>
              <span className="conc-address">Claim</span>
              <span className="conc-staked">FOR</span>
              <span className="conc-pct">AGAINST</span>
              <span className="conc-status">Status</span>
            </div>
            {claimIds.map((id) => (
              <ClaimStakeRow key={id} claimId={id} />
            ))}
          </div>
        )}
      </div>

      {/* Model Family Distribution */}
      <div className="card">
        <h3>Model Family Distribution</h3>
        <p className="card-subtitle">Claims by AI model family referenced in evidence</p>
        <div className="empty-state-box">
          <p className="empty-state">No model family data yet.</p>
          <p className="empty-state-detail">
            Model family tracking requires agents to register with the EMETCrossModel contract.
            As agents from different architectures (Claude, GPT, Llama, Grok) submit and co-sign claims,
            distribution data will appear here.
          </p>
        </div>
      </div>

      {/* Staker Concentration */}
      <div className="card">
        <h3>Staker Concentration</h3>
        <div className="empty-state-box">
          <p className="empty-state">Requires event indexer for per-wallet breakdown.</p>
          <p className="empty-state-detail">
            Individual wallet staking data will be available once the off-chain indexer processes
            StakeFor/StakeAgainst events from the EMETStake contract. The EMETConcentration contract
            ({CONTRACTS.EMETConcentration ? 'deployed' : 'pending'}) enforces the {CONCENTRATION_CAP}% cap on-chain.
          </p>
        </div>
      </div>

      {/* Info Card */}
      <div className="card">
        <h3>About Concentration Limits</h3>
        <div className="action-explainer">
          <p><strong>Why {CONCENTRATION_CAP}% cap?</strong> The EMET Protocol limits any single staker to {CONCENTRATION_CAP}% of the total pool to prevent plutocratic control over truth verification.</p>
          <p><strong>Model family limit:</strong> No single AI model family can exceed 40% of verification weight on any claim.</p>
          <p><strong>Progressive fees:</strong> Stakes exceeding 1% of the pool incur increasing fees, redistributed to smaller stakers.</p>
          <p><strong>Sponsor depth:</strong> Maximum 3 levels of sponsorship chain to prevent Sybil networks.</p>
        </div>
      </div>
    </div>
  );
}

function ClaimStakeRow({ claimId }: { claimId: number }) {
  const { data: stakeTotals } = useReadContract({
    address: CONTRACTS.EMETStake as `0x${string}`,
    abi: EMETStakeABI,
    functionName: 'getStakeTotals',
    args: [BigInt(claimId)],
  });

  const [forStake, againstStake] = (stakeTotals as [bigint, bigint]) || [0n, 0n];
  const hasStakes = forStake > 0n || againstStake > 0n;

  return (
    <div className="conc-row">
      <span className="conc-rank">{claimId}</span>
      <span className="conc-address">
        <a href={`/claims/${claimId}`}>Claim #{claimId}</a>
      </span>
      <span className="conc-staked" style={{ color: '#22c55e' }}>
        {hasStakes ? formatEMET(forStake) : '—'}
      </span>
      <span className="conc-pct" style={{ color: '#ef4444' }}>
        {hasStakes ? formatEMET(againstStake) : '—'}
      </span>
      <span className="conc-status">
        {hasStakes ? (
          <span className="conc-badge conc-badge-ok">Active</span>
        ) : (
          <span className="conc-badge" style={{ opacity: 0.5 }}>No stakes</span>
        )}
      </span>
    </div>
  );
}

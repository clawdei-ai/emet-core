import { useAccount } from 'wagmi';
import { Link } from 'react-router-dom';
import { useClaimCount, useClaims, useReputation, useReputationTier, useTokenBalance } from '../hooks/useProtocol';
import { ClaimStateBadge } from '../components/ClaimStateBadge';
import { formatEMET, shortenAddress, timeAgo, getClaimState, CLAIM_STATE_CONFIG, type ClaimState } from '../lib/format';

// Jury duties - read from chain when JuryPool indexer is available
// For now, empty array (no mock data)
const JURY_DUTIES: { claimId: number; role: string; status: 'active' | 'completed'; deadline: number; stakeRequired: string }[] = [];

function ReputationMeter({ score }: { score: number }) {
  const maxScore = 1000;
  const pct = Math.min(Math.max((score / maxScore) * 100, 0), 100);
  const color = score >= 500 ? '#22c55e' : score >= 200 ? '#eab308' : score >= 0 ? '#f97316' : '#ef4444';

  return (
    <div className="rep-meter">
      <div className="rep-meter-bar">
        <div className="rep-meter-fill" style={{ width: `${pct}%`, backgroundColor: color }} />
      </div>
      <div className="rep-meter-labels">
        <span>0</span>
        <span>{maxScore}</span>
      </div>
    </div>
  );
}

export function MyActivity() {
  const { address, isConnected } = useAccount();
  const { data: claimCount } = useClaimCount();
  const total = claimCount !== undefined ? Number(claimCount) : 0;

  const { data: claimsData, isLoading } = useClaims(0, Math.min(total, 50));
  const { data: reputation } = useReputation(address);
  const { data: tier } = useReputationTier(address);
  const { data: balance } = useTokenBalance(address);

  if (!isConnected) {
    return (
      <div className="page">
        <div className="card center-card">
          <h2>My Activity</h2>
          <p>Connect your wallet to view your activity.</p>
        </div>
      </div>
    );
  }

  const myClaims = (claimsData || [])
    .map((r, i) => {
      if (r.status !== 'success' || !r.result) return null;
      const c = r.result as {
        claimHash: string;
        claimText: string;
        evidenceURI: string;
        submitter: string;
        timestamp: bigint;
        stake: bigint;
        challengeEnd: bigint;
        status: number;
      };
      return { id: i, ...c, claimState: getClaimState(c.status, c.challengeEnd) };
    })
    .filter((c) => c && c.submitter.toLowerCase() === address?.toLowerCase())
    .reverse();

  const repScore = reputation !== undefined ? Number(reputation) : 0;

  // Count claims by state
  const stateCounts = myClaims.reduce((acc, c) => {
    if (c) {
      acc[c.claimState] = (acc[c.claimState] || 0) + 1;
    }
    return acc;
  }, {} as Record<ClaimState, number>);

  const activeJuryDuties = JURY_DUTIES.filter(j => j.status === 'active');

  return (
    <div className="page">
      <h1>My Activity</h1>

      {/* Stats */}
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-label">EMET Balance</div>
          <div className="stat-value">{balance !== undefined ? formatEMET(balance) : '—'}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Reputation Score</div>
          <div className="stat-value">{reputation !== undefined ? reputation.toString() : '—'}</div>
          {reputation !== undefined && <ReputationMeter score={repScore} />}
        </div>
        <div className="stat-card">
          <div className="stat-label">Tier</div>
          <div className="stat-value">{tier || '—'}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">My Claims</div>
          <div className="stat-value">{myClaims.length}</div>
        </div>
      </div>

      {/* Claim State Summary */}
      {myClaims.length > 0 && (
        <div className="card">
          <h3>Claim States</h3>
          <div className="state-summary">
            {(Object.entries(CLAIM_STATE_CONFIG) as [ClaimState, typeof CLAIM_STATE_CONFIG[ClaimState]][]).map(([state, config]) => (
              <div key={state} className={`state-summary-item state-summary-${state.toLowerCase()}`}>
                <span className="state-summary-icon">{config.icon}</span>
                <span className="state-summary-count">{stateCounts[state] || 0}</span>
                <span className="state-summary-label">{config.label}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Active Jury Duties */}
      <div className="card">
        <h3>Jury Duties</h3>
        {activeJuryDuties.length === 0 ? (
          <p className="empty-inline">No active jury duties. You may be selected as a juror when challenges arise.</p>
        ) : (
          <div className="jury-list">
            {activeJuryDuties.map((duty) => (
              <Link to={`/claims/${duty.claimId}`} key={duty.claimId} className="jury-item">
                <div className="jury-item-left">
                  <span className="jury-badge">⚖️ Juror</span>
                  <span>Claim #{duty.claimId}</span>
                </div>
                <div className="jury-item-right">
                  <span className="jury-stake">Stake: {duty.stakeRequired} EMET</span>
                  <span className="jury-deadline">
                    Deadline: {new Date(duty.deadline * 1000).toLocaleDateString()}
                  </span>
                </div>
              </Link>
            ))}
          </div>
        )}
        {JURY_DUTIES.filter(j => j.status === 'completed').length > 0 && (
          <div className="jury-completed">
            <h4>Completed</h4>
            {JURY_DUTIES.filter(j => j.status === 'completed').map((duty) => (
              <div key={duty.claimId} className="jury-item jury-item-completed">
                <span>⚖️ Claim #{duty.claimId}</span>
                <span className="jury-done">✓ Done</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* My Claims List */}
      <h2>My Claims</h2>
      <div className="claims-list">
        {isLoading && <p className="loading">Loading...</p>}
        {!isLoading && myClaims.length === 0 && (
          <div className="empty">
            <p>No claims yet.</p>
            <Link to="/submit" className="btn btn-primary">Submit your first claim</Link>
          </div>
        )}
        {myClaims.map((claim) => claim && (
          <Link to={`/claims/${claim.id}`} key={claim.id} className="claim-row">
            <div className="claim-row-header">
              <span className="claim-id">#{claim.id}</span>
              <ClaimStateBadge status={claim.status} challengeEnd={claim.challengeEnd} />
            </div>
            <div className="claim-row-body">
              <p className="claim-text-preview">
                {claim.claimText.length > 100 ? claim.claimText.slice(0, 100) + '...' : claim.claimText}
              </p>
            </div>
            <div className="claim-row-footer">
              <span>{shortenAddress(claim.submitter)}</span>
              <span>{formatEMET(claim.stake)} EMET staked</span>
              <span>{timeAgo(Number(claim.timestamp))}</span>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}

import { useAccount } from 'wagmi';
import { Link } from 'react-router-dom';
import { useClaimCount, useClaims, useReputation, useReputationTier, useTokenBalance } from '../hooks/useProtocol';
import { StatusBadge } from '../components/StatusBadge';
import { formatEMET, shortenAddress, timeAgo } from '../lib/format';

export function MyActivity() {
  const { address, isConnected } = useAccount();
  const { data: claimCount } = useClaimCount();
  const total = claimCount !== undefined ? Number(claimCount) : 0;

  // Fetch all claims (we'll filter client-side — fine for MVP)
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
        evidenceURI: string;
        submitter: string;
        timestamp: bigint;
        stake: bigint;
        challengeEnd: bigint;
        status: number;
      };
      return { id: i, ...c };
    })
    .filter((c) => c && c.submitter.toLowerCase() === address?.toLowerCase())
    .reverse();

  return (
    <div className="page">
      <h1>My Activity</h1>

      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-label">EMET Balance</div>
          <div className="stat-value">{balance !== undefined ? formatEMET(balance) : '—'}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Reputation</div>
          <div className="stat-value">{reputation !== undefined ? reputation.toString() : '—'}</div>
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
              <StatusBadge status={claim.status} />
            </div>
            <div className="claim-row-body">
              <span className="claim-evidence">
                {claim.evidenceURI.length > 60 ? claim.evidenceURI.slice(0, 60) + '...' : claim.evidenceURI}
              </span>
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

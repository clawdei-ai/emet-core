import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useClaimCount, useClaims } from '../hooks/useProtocol';
import { ClaimStateBadge } from '../components/ClaimStateBadge';
import { formatEMET, shortenAddress, timeAgo, getClaimState, type ClaimState } from '../lib/format';

const PAGE_SIZE = 10;

export function ClaimsList() {
  const { data: claimCount, isLoading } = useClaimCount();
  const total = claimCount !== undefined ? Number(claimCount) : 0;
  const [page, setPage] = useState(0);
  const [filterState, setFilterState] = useState<ClaimState | null>(null);

  const start = Math.max(0, total - (page + 1) * PAGE_SIZE);
  const count = Math.min(PAGE_SIZE, total - page * PAGE_SIZE);

  const { data: claimsData, isLoading: claimsLoading } = useClaims(start, count);

  if (isLoading) {
    return <div className="page"><p className="loading">Loading claims...</p></div>;
  }

  const claims = (claimsData || [])
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
      return { id: start + i, ...c, claimState: getClaimState(c.status, c.challengeEnd) };
    })
    .filter(Boolean)
    .filter((c) => filterState === null || c!.claimState === filterState)
    .reverse(); // newest first

  const totalPages = Math.ceil(total / PAGE_SIZE);

  return (
    <div className="page">
      <h1>Claims</h1>
      <p className="page-subtitle">{total} claims registered on the EMET Protocol</p>

      <div className="filter-bar">
        {([
          { value: null, label: 'All' },
          { value: 'PENDING' as ClaimState, label: '⏳ Pending' },
          { value: 'CONTESTED' as ClaimState, label: '⚔️ Contested' },
          { value: 'VERIFIED' as ClaimState, label: '✓ Verified' },
          { value: 'UNCONTESTED' as ClaimState, label: '○ Uncontested' },
          { value: 'REJECTED' as ClaimState, label: '✕ Rejected' },
        ]).map((f) => (
          <button
            key={String(f.value)}
            className={`filter-btn ${filterState === f.value ? 'active' : ''}`}
            onClick={() => setFilterState(f.value)}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="claims-list">
        {claimsLoading && <p className="loading">Loading...</p>}
        {!claimsLoading && claims.length === 0 && <p className="empty">No claims found.</p>}
        {claims.map((claim) => claim && (
          <Link to={`/claims/${claim.id}`} key={claim.id} className="claim-row">
            <div className="claim-row-header">
              <span className="claim-id">#{claim.id}</span>
              <ClaimStateBadge status={claim.status} challengeEnd={claim.challengeEnd} />
            </div>
            <div className="claim-row-body">
              <p className="claim-text-preview">
                {claim.claimText.length > 120 ? claim.claimText.slice(0, 120) + '...' : claim.claimText}
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

      {totalPages > 1 && (
        <div className="pagination">
          <button className="btn btn-small" disabled={page === 0} onClick={() => setPage(p => p - 1)}>← Newer</button>
          <span>Page {page + 1} of {totalPages}</span>
          <button className="btn btn-small" disabled={page >= totalPages - 1} onClick={() => setPage(p => p + 1)}>Older →</button>
        </div>
      )}
    </div>
  );
}

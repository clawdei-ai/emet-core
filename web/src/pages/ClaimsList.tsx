import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useClaimCount, useClaims } from '../hooks/useProtocol';
import { StatusBadge } from '../components/StatusBadge';
import { formatEMET, shortenAddress, timeAgo } from '../lib/format';

const PAGE_SIZE = 10;

export function ClaimsList() {
  const { data: claimCount, isLoading } = useClaimCount();
  const total = claimCount !== undefined ? Number(claimCount) : 0;
  const [page, setPage] = useState(0);
  const [filterStatus, setFilterStatus] = useState<number | null>(null);

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
        evidenceURI: string;
        submitter: string;
        timestamp: bigint;
        stake: bigint;
        challengeEnd: bigint;
        status: number;
      };
      return { id: start + i, ...c };
    })
    .filter(Boolean)
    .filter((c) => filterStatus === null || c!.status === filterStatus)
    .reverse(); // newest first

  const totalPages = Math.ceil(total / PAGE_SIZE);

  return (
    <div className="page">
      <h1>Claims</h1>
      <p className="page-subtitle">{total} claims registered on the EMET Protocol</p>

      <div className="filter-bar">
        {[
          { value: null, label: 'All' },
          { value: 0, label: 'Active' },
          { value: 1, label: 'Challenged' },
          { value: 2, label: 'Verified' },
          { value: 3, label: 'Rejected' },
        ].map((f) => (
          <button
            key={String(f.value)}
            className={`filter-btn ${filterStatus === f.value ? 'active' : ''}`}
            onClick={() => setFilterStatus(f.value)}
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
              <StatusBadge status={claim.status} />
            </div>
            <div className="claim-row-body">
              <span className="claim-evidence" title={claim.evidenceURI}>
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

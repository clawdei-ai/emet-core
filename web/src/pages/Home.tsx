import { useClaimCount, useMinimumStake, useChallengePeriod } from '../hooks/useProtocol';
import { formatEMET } from '../lib/format';
import { Link } from 'react-router-dom';

export function Home() {
  const { data: claimCount } = useClaimCount();
  const { data: minimumStake } = useMinimumStake();
  const { data: challengePeriod } = useChallengePeriod();

  return (
    <div className="page">
      <div className="hero">
        <h1>EMET Protocol</h1>
        <p className="subtitle">Trustless truth verification on Base. Submit claims, stake on truth, challenge lies.</p>
        <div className="hero-actions">
          <Link to="/submit" className="btn btn-primary">Submit a Claim</Link>
          <Link to="/claims" className="btn btn-secondary">Browse Claims</Link>
        </div>
      </div>

      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-label">Total Claims</div>
          <div className="stat-value">{claimCount !== undefined ? claimCount.toString() : '—'}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Min Stake</div>
          <div className="stat-value">{minimumStake ? `${formatEMET(minimumStake)} EMET` : '—'}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Challenge Period</div>
          <div className="stat-value">{challengePeriod ? `${Number(challengePeriod) / 86400}d` : '—'}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Network</div>
          <div className="stat-value">Base</div>
        </div>
      </div>

      <section className="info-section">
        <h2>How it works</h2>
        <div className="steps-grid">
          <div className="step">
            <div className="step-number">1</div>
            <h3>Submit</h3>
            <p>Make a verifiable claim with evidence and stake EMET tokens as collateral.</p>
          </div>
          <div className="step">
            <div className="step-number">2</div>
            <h3>Challenge</h3>
            <p>Anyone can challenge claims they believe are false by staking against them.</p>
          </div>
          <div className="step">
            <div className="step-number">3</div>
            <h3>Resolve</h3>
            <p>Stake-weighted resolution determines truth. Winners earn rewards, liars lose their stake.</p>
          </div>
        </div>
      </section>
    </div>
  );
}

import { useMemo } from 'react';
import { shortenAddress, formatEMET } from '../lib/format';

// ============ Mock Data ============
// In production, this would come from on-chain events / indexer

interface StakerInfo {
  address: string;
  totalStaked: bigint;
  claimCount: number;
  avgStakePerClaim: bigint;
}

const MOCK_TOTAL_POOL = 5_000_000n * 10n ** 18n; // 5M EMET total pool

const MOCK_STAKERS: StakerInfo[] = [
  { address: '0x1a2b3c4d5e6f7890abcdef1234567890abcdef12', totalStaked: 420_000n * 10n ** 18n, claimCount: 12, avgStakePerClaim: 35_000n * 10n ** 18n },
  { address: '0x2b3c4d5e6f7890abcdef1234567890abcdef1234', totalStaked: 380_000n * 10n ** 18n, claimCount: 8, avgStakePerClaim: 47_500n * 10n ** 18n },
  { address: '0x3c4d5e6f7890abcdef1234567890abcdef123456', totalStaked: 310_000n * 10n ** 18n, claimCount: 15, avgStakePerClaim: 20_667n * 10n ** 18n },
  { address: '0x4d5e6f7890abcdef1234567890abcdef12345678', totalStaked: 275_000n * 10n ** 18n, claimCount: 6, avgStakePerClaim: 45_833n * 10n ** 18n },
  { address: '0x5e6f7890abcdef1234567890abcdef1234567890', totalStaked: 240_000n * 10n ** 18n, claimCount: 22, avgStakePerClaim: 10_909n * 10n ** 18n },
  { address: '0x6f7890abcdef1234567890abcdef123456789012', totalStaked: 195_000n * 10n ** 18n, claimCount: 4, avgStakePerClaim: 48_750n * 10n ** 18n },
  { address: '0x7890abcdef1234567890abcdef12345678901234', totalStaked: 170_000n * 10n ** 18n, claimCount: 9, avgStakePerClaim: 18_889n * 10n ** 18n },
  { address: '0x890abcdef1234567890abcdef1234567890123456', totalStaked: 150_000n * 10n ** 18n, claimCount: 7, avgStakePerClaim: 21_429n * 10n ** 18n },
  { address: '0x90abcdef1234567890abcdef12345678901234567', totalStaked: 125_000n * 10n ** 18n, claimCount: 3, avgStakePerClaim: 41_667n * 10n ** 18n },
  { address: '0xabcdef1234567890abcdef123456789012345678', totalStaked: 110_000n * 10n ** 18n, claimCount: 11, avgStakePerClaim: 10_000n * 10n ** 18n },
];

const MOCK_MODEL_FAMILIES = [
  { name: 'GPT-4', claims: 28, percentage: 35, color: '#6366f1' },
  { name: 'Claude', claims: 22, percentage: 27.5, color: '#f97316' },
  { name: 'Gemini', claims: 14, percentage: 17.5, color: '#22c55e' },
  { name: 'Llama', claims: 8, percentage: 10, color: '#eab308' },
  { name: 'Mistral', claims: 5, percentage: 6.25, color: '#ef4444' },
  { name: 'Other', claims: 3, percentage: 3.75, color: '#9ca3af' },
];

const CONCENTRATION_CAP = 5; // 5% max per staker

export function Concentration() {
  const stakers = useMemo(() => {
    return MOCK_STAKERS.map(s => {
      const pct = Number((s.totalStaked * 10000n) / MOCK_TOTAL_POOL) / 100;
      return { ...s, percentage: pct, nearCap: pct >= CONCENTRATION_CAP * 0.8, overCap: pct >= CONCENTRATION_CAP };
    });
  }, []);

  const topStakerPct = stakers.reduce((sum, s) => sum + s.percentage, 0);

  return (
    <div className="page">
      <h1>Concentration Dashboard</h1>
      <p className="page-subtitle">Monitor staking concentration and model family distribution across the EMET Protocol.</p>

      {/* Summary Stats */}
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-label">Total Pool</div>
          <div className="stat-value">{formatEMET(MOCK_TOTAL_POOL)}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Top 10 Share</div>
          <div className="stat-value">{topStakerPct.toFixed(1)}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Concentration Cap</div>
          <div className="stat-value">{CONCENTRATION_CAP}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">At-Risk Wallets</div>
          <div className="stat-value concentration-warning">{stakers.filter(s => s.nearCap).length}</div>
        </div>
      </div>

      {/* Top Stakers Table */}
      <div className="card">
        <h3>Top 10 Stakers by Pool Share</h3>
        <div className="concentration-table">
          <div className="conc-header">
            <span className="conc-rank">#</span>
            <span className="conc-address">Address</span>
            <span className="conc-staked">Total Staked</span>
            <span className="conc-pct">% of Pool</span>
            <span className="conc-claims">Claims</span>
            <span className="conc-status">Status</span>
          </div>
          {stakers.map((s, i) => (
            <div key={s.address} className={`conc-row ${s.overCap ? 'conc-row-danger' : s.nearCap ? 'conc-row-warning' : ''}`}>
              <span className="conc-rank">{i + 1}</span>
              <span className="conc-address">
                <a href={`https://basescan.org/address/${s.address}`} target="_blank" rel="noreferrer">
                  {shortenAddress(s.address)}
                </a>
              </span>
              <span className="conc-staked">{formatEMET(s.totalStaked)}</span>
              <span className="conc-pct">
                <div className="conc-bar-wrapper">
                  <div
                    className={`conc-bar ${s.overCap ? 'conc-bar-danger' : s.nearCap ? 'conc-bar-warning' : 'conc-bar-ok'}`}
                    style={{ width: `${Math.min(s.percentage / CONCENTRATION_CAP * 100, 100)}%` }}
                  />
                </div>
                <span>{s.percentage.toFixed(2)}%</span>
              </span>
              <span className="conc-claims">{s.claimCount}</span>
              <span className="conc-status">
                {s.overCap && <span className="conc-badge conc-badge-danger">⚠ OVER CAP</span>}
                {s.nearCap && !s.overCap && <span className="conc-badge conc-badge-warning">⚡ NEAR CAP</span>}
                {!s.nearCap && <span className="conc-badge conc-badge-ok">✓ OK</span>}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Model Family Distribution */}
      <div className="card">
        <h3>Model Family Distribution</h3>
        <p className="card-subtitle">Claims by AI model family referenced in evidence</p>
        <div className="model-dist">
          {/* Visual pie/donut representation */}
          <div className="model-chart">
            <svg viewBox="0 0 200 200" className="donut-chart">
              {(() => {
                let offset = 0;
                return MOCK_MODEL_FAMILIES.map((m) => {
                  const dashArray = m.percentage * 3.14159; // circumference fraction
                  const dashOffset = -offset * 3.14159;
                  offset += m.percentage;
                  return (
                    <circle
                      key={m.name}
                      cx="100"
                      cy="100"
                      r="50"
                      fill="none"
                      stroke={m.color}
                      strokeWidth="30"
                      strokeDasharray={`${dashArray} ${314.159 - dashArray}`}
                      strokeDashoffset={dashOffset}
                      className="donut-segment"
                    />
                  );
                });
              })()}
              <text x="100" y="95" textAnchor="middle" className="donut-center-text" fill="#e4e4ed" fontSize="16" fontWeight="700">80</text>
              <text x="100" y="115" textAnchor="middle" className="donut-center-sub" fill="#888899" fontSize="10">claims</text>
            </svg>
          </div>
          <div className="model-legend">
            {MOCK_MODEL_FAMILIES.map((m) => (
              <div key={m.name} className="model-legend-item">
                <span className="model-legend-color" style={{ backgroundColor: m.color }} />
                <span className="model-legend-name">{m.name}</span>
                <span className="model-legend-claims">{m.claims} claims</span>
                <span className="model-legend-pct">{m.percentage}%</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Info Card */}
      <div className="card">
        <h3>About Concentration Limits</h3>
        <div className="action-explainer">
          <p><strong>Why {CONCENTRATION_CAP}% cap?</strong> The EMET Protocol limits any single staker to {CONCENTRATION_CAP}% of the total pool to prevent plutocratic control over truth verification.</p>
          <p><strong>What happens at the cap?</strong> Wallets exceeding the cap cannot submit new stakes until their share decreases below the threshold.</p>
          <p><strong>Near-cap warnings</strong> appear when a wallet reaches 80% of the concentration limit ({(CONCENTRATION_CAP * 0.8).toFixed(1)}%).</p>
        </div>
      </div>
    </div>
  );
}

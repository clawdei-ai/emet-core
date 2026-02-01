import { type ClaimState, CLAIM_STATE_CONFIG, getClaimState } from '../lib/format';

interface ClaimStateBadgeProps {
  status: number;
  challengeEnd: bigint;
  size?: 'sm' | 'md';
}

export function ClaimStateBadge({ status, challengeEnd, size = 'md' }: ClaimStateBadgeProps) {
  const state = getClaimState(status, challengeEnd);
  const config = CLAIM_STATE_CONFIG[state];

  return (
    <span
      className={`claim-state-badge claim-state-${state.toLowerCase()} ${size === 'sm' ? 'claim-state-sm' : ''}`}
      title={config.description}
    >
      <span className="claim-state-icon">{config.icon}</span>
      {config.label}
    </span>
  );
}

/** Standalone badge from a pre-computed state */
export function StateBadge({ state }: { state: ClaimState }) {
  const config = CLAIM_STATE_CONFIG[state];
  return (
    <span
      className={`claim-state-badge claim-state-${state.toLowerCase()}`}
      title={config.description}
    >
      <span className="claim-state-icon">{config.icon}</span>
      {config.label}
    </span>
  );
}

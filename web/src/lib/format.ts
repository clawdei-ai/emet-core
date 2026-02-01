import { formatUnits } from 'viem';

export function formatEMET(value: bigint, decimals = 18): string {
  const num = Number(formatUnits(value, decimals));
  if (num >= 1_000_000) return `${(num / 1_000_000).toFixed(1)}M`;
  if (num >= 1_000) return `${(num / 1_000).toFixed(1)}K`;
  return num.toFixed(num < 1 ? 4 : 2);
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

// On-chain status codes
export const STATUS_LABELS: Record<number, string> = {
  0: 'Active',
  1: 'Challenged',
  2: 'Verified',
  3: 'Rejected',
};

export const STATUS_COLORS: Record<number, string> = {
  0: '#3b82f6', // blue
  1: '#f59e0b', // amber
  2: '#10b981', // green
  3: '#ef4444', // red
};

// ============ Derived Claim States ============
// These are UI-level states derived from on-chain status + timing

export type ClaimState = 'PENDING' | 'CONTESTED' | 'VERIFIED' | 'UNCONTESTED' | 'REJECTED';

export const CLAIM_STATE_CONFIG: Record<ClaimState, { label: string; color: string; icon: string; description: string }> = {
  PENDING:      { label: 'Pending',      color: '#eab308', icon: '⏳', description: 'Within challenge window' },
  CONTESTED:    { label: 'Contested',    color: '#f97316', icon: '⚔️', description: 'Has active challenge' },
  VERIFIED:     { label: 'Verified',     color: '#22c55e', icon: '✓',  description: 'Challenged and won' },
  UNCONTESTED:  { label: 'Uncontested',  color: '#9ca3af', icon: '○',  description: 'Expired without challenge' },
  REJECTED:     { label: 'Rejected',     color: '#ef4444', icon: '✕',  description: 'Challenged and lost' },
};

/**
 * Derive the UI claim state from on-chain status and challenge end timestamp.
 * On-chain status: 0=Active, 1=Challenged, 2=Verified, 3=Rejected
 */
export function getClaimState(status: number, challengeEnd: bigint): ClaimState {
  switch (status) {
    case 0: {
      const now = BigInt(Math.floor(Date.now() / 1000));
      if (challengeEnd > 0n && challengeEnd <= now) {
        return 'UNCONTESTED';
      }
      return 'PENDING';
    }
    case 1:
      return 'CONTESTED';
    case 2:
      return 'VERIFIED';
    case 3:
      return 'REJECTED';
    default:
      return 'PENDING';
  }
}

export function timeAgo(timestamp: number): string {
  const diff = Date.now() / 1000 - timestamp;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

export function timeRemaining(timestamp: number): string {
  const diff = timestamp - Date.now() / 1000;
  if (diff <= 0) return 'ended';
  if (diff < 3600) return `${Math.floor(diff / 60)}m left`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h left`;
  return `${Math.floor(diff / 86400)}d left`;
}

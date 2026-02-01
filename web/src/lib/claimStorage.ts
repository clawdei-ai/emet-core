// Local storage for claim texts (since only hash is stored on-chain)
const STORAGE_KEY = 'emet_claims';

interface StoredClaims {
  [claimHash: string]: {
    text: string;
    submittedAt: number;
  };
}

export function saveClaim(claimHash: string, text: string) {
  const stored = getClaims();
  stored[claimHash] = { text, submittedAt: Date.now() };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
}

export function getClaims(): StoredClaims {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
  } catch {
    return {};
  }
}

export function getClaimText(claimHash: string): string | null {
  const claims = getClaims();
  return claims[claimHash]?.text || null;
}

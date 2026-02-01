// Fetches known claim texts from the public claims index
// This provides a fallback for claims where text isn't stored locally

export interface ClaimEntry {
  text: string | null;
  note?: string;
  evidenceNote?: string;
  claimId: number;
  submitter: string;
  addedAt: string;
}

interface ClaimsIndex {
  version: number;
  claims: Record<string, ClaimEntry>;
}

let cachedIndex: ClaimsIndex | null = null;

export async function fetchClaimsIndex(): Promise<ClaimsIndex> {
  if (cachedIndex) return cachedIndex;
  
  try {
    const res = await fetch('/claims-index.json');
    if (!res.ok) throw new Error('Failed to fetch');
    cachedIndex = await res.json();
    return cachedIndex!;
  } catch {
    return { version: 0, claims: {} };
  }
}

export async function getClaimTextFromIndex(claimHash: string): Promise<string | null> {
  const index = await fetchClaimsIndex();
  return index.claims[claimHash]?.text || null;
}

export async function getClaimEntryFromIndex(claimHash: string): Promise<ClaimEntry | null> {
  const index = await fetchClaimsIndex();
  return index.claims[claimHash] || null;
}

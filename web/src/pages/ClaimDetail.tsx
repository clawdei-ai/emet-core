import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { useAccount } from 'wagmi';
import { parseUnits, keccak256, toBytes } from 'viem';
import {
  useClaim, useStakeTotals, useUserStakes, useChallenge, useCanResolve,
  useStakeFor, useInitiateChallenge, useResolveChallenge, useVerifyUnchallenged,
  useApproveEMET, useTokenAllowance,
} from '../hooks/useProtocol';
import { CONTRACTS } from '../contracts/addresses';
import { StatusBadge } from '../components/StatusBadge';
import { formatEMET, shortenAddress, timeAgo, timeRemaining } from '../lib/format';
import { getClaimText, saveClaim } from '../lib/claimStorage';
import { getClaimTextFromIndex } from '../lib/claimsIndex';

export function ClaimDetail() {
  const { id } = useParams<{ id: string }>();
  const claimId = BigInt(id || '0');
  const { address } = useAccount();

  const { data: claim, isLoading } = useClaim(claimId);
  const { data: stakeTotals } = useStakeTotals(claimId);
  const { data: userStakes } = useUserStakes(claimId, address);
  const { data: challenge } = useChallenge(claimId);
  const { data: canResolve } = useCanResolve(claimId);

  const [stakeAmount, setStakeAmount] = useState('100');
  const [action, setAction] = useState<'none' | 'stakeFor' | 'challenge'>('none');
  const [manualClaimText, setManualClaimText] = useState('');
  const [verificationStatus, setVerificationStatus] = useState<'none' | 'valid' | 'invalid'>('none');
  const [indexedClaimText, setIndexedClaimText] = useState<string | null>(null);

  // Write hooks
  const stakeForHook = useStakeFor();
  const challengeHook = useInitiateChallenge();
  const resolveHook = useResolveChallenge();
  const verifyHook = useVerifyUnchallenged();
  const approveHook = useApproveEMET();
  const { data: allowance, refetch: refetchAllowance } = useTokenAllowance(
    address,
    action === 'stakeFor' ? CONTRACTS.EMETStake : CONTRACTS.EMETChallenge
  );

  useEffect(() => {
    if (approveHook.isSuccess) refetchAllowance();
  }, [approveHook.isSuccess, refetchAllowance]);

  // Fetch claim text from public index if not stored locally
  useEffect(() => {
    if (claim && !getClaimText((claim as { claimHash: string }).claimHash)) {
      getClaimTextFromIndex((claim as { claimHash: string }).claimHash).then((text) => {
        if (text) {
          setIndexedClaimText(text);
          // Cache locally for future visits
          saveClaim((claim as { claimHash: string }).claimHash, text);
        }
      });
    }
  }, [claim]);

  if (isLoading) return <div className="page"><p className="loading">Loading claim...</p></div>;
  if (!claim) return <div className="page"><p className="empty">Claim not found.</p></div>;

  const c = claim as {
    claimHash: string;
    evidenceURI: string;
    submitter: string;
    timestamp: bigint;
    stake: bigint;
    challengeEnd: bigint;
    status: number;
  };

  // Try to get claim text from local storage or index
  const storedClaimText = getClaimText(c.claimHash);
  const claimText = storedClaimText || indexedClaimText || (verificationStatus === 'valid' ? manualClaimText : null);

  const verifyClaimText = () => {
    if (!manualClaimText.trim()) return;
    const computedHash = keccak256(toBytes(manualClaimText));
    if (computedHash === c.claimHash) {
      setVerificationStatus('valid');
      // Save for future visits
      saveClaim(c.claimHash, manualClaimText);
    } else {
      setVerificationStatus('invalid');
    }
  };

  const totalFor = stakeTotals ? (stakeTotals as [bigint, bigint])[0] : 0n;
  const totalAgainst = stakeTotals ? (stakeTotals as [bigint, bigint])[1] : 0n;
  const myFor = userStakes ? (userStakes as [bigint, bigint])[0] : 0n;
  const myAgainst = userStakes ? (userStakes as [bigint, bigint])[1] : 0n;

  const stakeWei = stakeAmount ? parseUnits(stakeAmount, 18) : 0n;
  const needsApproval = allowance !== undefined && stakeWei > allowance;

  const handleStakeFor = () => {
    setAction('stakeFor');
    if (needsApproval) {
      approveHook.approve(CONTRACTS.EMETStake, stakeWei);
    } else {
      stakeForHook.stakeFor(claimId, stakeAmount);
    }
  };

  const handleChallenge = () => {
    setAction('challenge');
    if (needsApproval) {
      approveHook.approve(CONTRACTS.EMETChallenge, stakeWei);
    } else {
      challengeHook.challenge(claimId, stakeAmount);
    }
  };

  return (
    <div className="page">
      <div className="claim-detail-header">
        <h1>Claim #{id}</h1>
        <StatusBadge status={c.status} />
      </div>

      <div className="detail-grid">
        <div className="card">
          <h3>Claim Info</h3>
          
          {/* Show claim text prominently if available */}
          {claimText ? (
            <div className="claim-text-box">
              <span className="detail-label">Claim Statement {verificationStatus === 'valid' && '✓ Verified'}</span>
              <p className="claim-text">{claimText}</p>
            </div>
          ) : (
            <div className="claim-text-box claim-text-missing">
              <span className="detail-label">Claim Statement</span>
              <p className="claim-text-note">
                Claim text not stored locally. <strong>Check the evidence link below</strong> — it may contain the original text.
                Or paste it here to verify:
              </p>
              <div className="verify-form">
                <textarea
                  value={manualClaimText}
                  onChange={(e) => { setManualClaimText(e.target.value); setVerificationStatus('none'); }}
                  placeholder="Paste the original claim text to verify it matches the hash..."
                  rows={3}
                />
                <button className="btn btn-secondary" onClick={verifyClaimText}>
                  Verify Text Matches Hash
                </button>
                {verificationStatus === 'invalid' && (
                  <p className="verify-error">✗ Text doesn't match the on-chain hash. Check for typos or extra whitespace.</p>
                )}
              </div>
            </div>
          )}

          <div className="detail-row">
            <span className="detail-label">Submitter</span>
            <a href={`https://basescan.org/address/${c.submitter}`} target="_blank" rel="noreferrer">
              {shortenAddress(c.submitter)}
            </a>
          </div>
          <div className="detail-row">
            <span className="detail-label">Fingerprint (Hash)</span>
            <code className="hash" title="keccak256 hash of the claim text">{c.claimHash.slice(0, 18)}...</code>
          </div>
          <div className="detail-row">
            <span className="detail-label">Evidence</span>
            <a href={c.evidenceURI} target="_blank" rel="noreferrer" className="evidence-link">
              {c.evidenceURI.length > 50 ? c.evidenceURI.slice(0, 50) + '...' : c.evidenceURI}
            </a>
          </div>
          <div className="detail-row">
            <span className="detail-label">Submitted</span>
            <span>{timeAgo(Number(c.timestamp))} · {new Date(Number(c.timestamp) * 1000).toLocaleString()}</span>
          </div>
          <div className="detail-row">
            <span className="detail-label">Submitter Stake</span>
            <span>{formatEMET(c.stake)} EMET</span>
          </div>
          {c.challengeEnd > 0n && (
            <div className="detail-row">
              <span className="detail-label">Challenge Period</span>
              <span>{timeRemaining(Number(c.challengeEnd))}</span>
            </div>
          )}
        </div>

        <div className="card">
          <h3>Stake Market</h3>
          <div className="stake-bar-container">
            <div className="stake-bar">
              <div
                className="stake-bar-for"
                style={{ width: `${totalFor + totalAgainst > 0n ? Number((totalFor * 100n) / (totalFor + totalAgainst)) : 50}%` }}
              />
            </div>
            <div className="stake-labels">
              <span className="stake-for">{formatEMET(totalFor)} FOR</span>
              <span className="stake-against">{formatEMET(totalAgainst)} AGAINST</span>
            </div>
          </div>

          {address && (myFor > 0n || myAgainst > 0n) && (
            <div className="my-stakes">
              <h4>Your Stakes</h4>
              {myFor > 0n && <p className="stake-for">For: {formatEMET(myFor)} EMET</p>}
              {myAgainst > 0n && <p className="stake-against">Against: {formatEMET(myAgainst)} EMET</p>}
            </div>
          )}

          {challenge && (challenge as [string, bigint, bigint, boolean])[0] !== '0x0000000000000000000000000000000000000000' && (
            <div className="challenge-info">
              <h4>Challenge</h4>
              <p>
                Challenger: {shortenAddress((challenge as [string, bigint, bigint, boolean])[0])}
                <br />
                Stake: {formatEMET((challenge as [string, bigint, bigint, boolean])[1])} EMET
              </p>
            </div>
          )}
        </div>
      </div>

      {/* Actions */}
      {address && (c.status === 0 || c.status === 1) && (
        <div className="card action-card">
          <h3>Take Action</h3>
          
          {c.status === 0 && (
            <div className="action-explainer">
              <p><strong>🟢 Stake For:</strong> You believe this claim is TRUE. Stake EMET to support it and earn rewards if verified.</p>
              <p><strong>🔴 Challenge:</strong> You believe this claim is FALSE. Stake EMET to dispute it. If you're right, you win the submitter's stake.</p>
            </div>
          )}
          
          {c.status === 1 && (
            <div className="action-explainer">
              <p>⚠️ This claim is being challenged. You can still stake FOR it if you believe it's true.</p>
            </div>
          )}

          <div className="form-group">
            <label>Stake Amount (EMET)</label>
            <input
              type="number"
              value={stakeAmount}
              onChange={(e) => setStakeAmount(e.target.value)}
              min="100"
              step="1"
            />
          </div>
          <div className="action-buttons">
            {c.status === 0 && (
              <>
                <button className="btn btn-primary" onClick={handleStakeFor} disabled={stakeForHook.isPending}>
                  🟢 Stake FOR (It's True)
                </button>
                <button className="btn btn-danger" onClick={handleChallenge} disabled={challengeHook.isPending}>
                  🔴 Challenge (It's False)
                </button>
              </>
            )}
            {c.status === 1 && (
              <button className="btn btn-primary" onClick={handleStakeFor} disabled={stakeForHook.isPending}>
                🟢 Stake FOR (It's True)
              </button>
            )}
          </div>

          {(stakeForHook.isPending || stakeForHook.isConfirming) && <p className="tx-status">⏳ Staking...</p>}
          {stakeForHook.isSuccess && <p className="tx-status success">✓ Staked successfully!</p>}
          {(challengeHook.isPending || challengeHook.isConfirming) && <p className="tx-status">⏳ Challenging...</p>}
          {challengeHook.isSuccess && <p className="tx-status success">✓ Challenge initiated!</p>}
          {(approveHook.isPending || approveHook.isConfirming) && <p className="tx-status">⏳ Approving tokens...</p>}
        </div>
      )}

      {/* Resolve / Verify */}
      {c.status === 1 && canResolve && (
        <div className="card action-card">
          <button className="btn btn-primary btn-full" onClick={() => resolveHook.resolve(claimId)} disabled={resolveHook.isPending}>
            Resolve Challenge
          </button>
          {resolveHook.isConfirming && <p className="tx-status">⏳ Resolving...</p>}
          {resolveHook.isSuccess && <p className="tx-status success">✓ Challenge resolved!</p>}
        </div>
      )}

      {c.status === 0 && (
        <div className="card action-card">
          <button className="btn btn-secondary btn-full" onClick={() => verifyHook.verify(claimId)} disabled={verifyHook.isPending}>
            Verify (if challenge period ended)
          </button>
          {verifyHook.isConfirming && <p className="tx-status">⏳ Verifying...</p>}
          {verifyHook.isSuccess && <p className="tx-status success">✓ Claim verified!</p>}
          {verifyHook.error && <p className="tx-status error">Challenge period not over yet.</p>}
        </div>
      )}
    </div>
  );
}

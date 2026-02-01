import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { useAccount } from 'wagmi';
import { parseUnits } from 'viem';
import {
  useClaim, useStakeTotals, useUserStakes, useChallenge, useCanResolve,
  useStakeFor, useInitiateChallenge, useResolveChallenge, useVerifyUnchallenged,
  useApproveEMET, useTokenAllowance,
} from '../hooks/useProtocol';
import { CONTRACTS } from '../contracts/addresses';
import { ClaimStateBadge } from '../components/ClaimStateBadge';
import { ChallengeForm } from '../components/ChallengeForm';
import { formatEMET, shortenAddress, timeAgo, timeRemaining, getClaimState, CLAIM_STATE_CONFIG } from '../lib/format';

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

  // After approval succeeds, auto-submit the pending action
  useEffect(() => {
    if (approveHook.isSuccess) {
      refetchAllowance().then(() => {
        if (action === 'stakeFor') {
          stakeForHook.stakeFor(claimId, stakeAmount);
        } else if (action === 'challenge') {
          challengeHook.challenge(claimId, stakeAmount, '', 0);
        }
      });
    }
  }, [approveHook.isSuccess]);

  if (isLoading) return <div className="page"><p className="loading">Loading claim...</p></div>;
  if (!claim) return <div className="page"><p className="empty">Claim not found.</p></div>;

  const c = claim as {
    claimHash: string;
    claimText: string;
    evidenceURI: string;
    submitter: string;
    timestamp: bigint;
    stake: bigint;
    challengeEnd: bigint;
    status: number;
  };

  const claimState = getClaimState(c.status, c.challengeEnd);
  const stateConfig = CLAIM_STATE_CONFIG[claimState];

  const totalFor = stakeTotals ? (stakeTotals as [bigint, bigint])[0] : 0n;
  const totalAgainst = stakeTotals ? (stakeTotals as [bigint, bigint])[1] : 0n;
  const myFor = userStakes ? (userStakes as [bigint, bigint])[0] : 0n;
  const myAgainst = userStakes ? (userStakes as [bigint, bigint])[1] : 0n;

  const stakeWei = stakeAmount ? parseUnits(stakeAmount, 18) : 0n;
  const needsApproval = allowance !== undefined && stakeWei > allowance;

  const challengeData = challenge as [string, bigint, bigint, boolean] | undefined;
  const hasChallenge = challengeData && challengeData[0] !== '0x0000000000000000000000000000000000000000';

  const handleStakeFor = () => {
    setAction('stakeFor');
    if (needsApproval) {
      approveHook.approve(CONTRACTS.EMETStake, stakeWei);
    } else {
      stakeForHook.stakeFor(claimId, stakeAmount);
    }
  };

  return (
    <div className="page">
      <div className="claim-detail-header">
        <h1>Claim #{id}</h1>
        <ClaimStateBadge status={c.status} challengeEnd={c.challengeEnd} />
      </div>

      {/* State explanation banner */}
      <div className={`state-banner state-banner-${claimState.toLowerCase()}`}>
        <span className="state-banner-icon">{stateConfig.icon}</span>
        <span>{stateConfig.description}</span>
      </div>

      <div className="detail-grid">
        <div className="card">
          <h3>Claim Info</h3>
          
          <div className="claim-text-box">
            <span className="detail-label">Claim Statement</span>
            <p className="claim-text">{c.claimText}</p>
          </div>

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

          {/* Existing Challenge Display */}
          {hasChallenge && (
            <div className="challenge-info">
              <h4>⚔️ Active Challenge</h4>
              <div className="challenge-details">
                <div className="detail-row">
                  <span className="detail-label">Challenger</span>
                  <a href={`https://basescan.org/address/${challengeData![0]}`} target="_blank" rel="noreferrer">
                    {shortenAddress(challengeData![0])}
                  </a>
                </div>
                <div className="detail-row">
                  <span className="detail-label">Challenge Stake</span>
                  <span className="stake-against">{formatEMET(challengeData![1])} EMET</span>
                </div>
                <div className="detail-row">
                  <span className="detail-label">Started</span>
                  <span>{timeAgo(Number(challengeData![2]))}</span>
                </div>
                <div className="detail-row">
                  <span className="detail-label">Resolved</span>
                  <span>{challengeData![3] ? '✓ Yes' : '✕ Not yet'}</span>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Challenge This Claim - Only for PENDING claims */}
      {address && claimState === 'PENDING' && !hasChallenge && (
        <div className="card action-card">
          <ChallengeForm claimId={claimId} />
        </div>
      )}

      {/* Stake For - for active/contested claims */}
      {address && (c.status === 0 || c.status === 1) && (
        <div className="card action-card">
          <h3>Stake For This Claim</h3>
          
          {c.status === 0 && !hasChallenge && (
            <div className="action-explainer">
              <p><strong>🟢 Support:</strong> You believe this claim is TRUE. Stake EMET to support it and earn rewards if verified.</p>
            </div>
          )}
          
          {c.status === 1 && (
            <div className="action-explainer">
              <p>⚠️ This claim is being challenged. Stake FOR it if you believe it's true — your stake strengthens the claim's defense.</p>
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
            <button className="btn btn-primary" onClick={handleStakeFor} disabled={stakeForHook.isPending}>
              🟢 Stake FOR (It's True)
            </button>
          </div>

          {(stakeForHook.isPending || stakeForHook.isConfirming) && <p className="tx-status">⏳ Staking...</p>}
          {stakeForHook.isSuccess && <p className="tx-status success">✓ Staked successfully!</p>}
          {(approveHook.isPending || approveHook.isConfirming) && <p className="tx-status">⏳ Approving tokens...</p>}
        </div>
      )}

      {/* Resolve Challenge */}
      {c.status === 1 && canResolve && (
        <div className="card action-card">
          <button className="btn btn-primary btn-full" onClick={() => resolveHook.resolve(claimId)} disabled={resolveHook.isPending}>
            ⚖️ Resolve Challenge
          </button>
          {resolveHook.isConfirming && <p className="tx-status">⏳ Resolving...</p>}
          {resolveHook.isSuccess && <p className="tx-status success">✓ Challenge resolved!</p>}
        </div>
      )}

      {/* Verify Unchallenged */}
      {claimState === 'UNCONTESTED' && (
        <div className="card action-card">
          <div className="action-explainer">
            <p>The challenge period has ended with no challenges. This claim can now be verified.</p>
          </div>
          <button className="btn btn-secondary btn-full" onClick={() => verifyHook.verify(claimId)} disabled={verifyHook.isPending}>
            ✓ Verify Unchallenged Claim
          </button>
          {verifyHook.isConfirming && <p className="tx-status">⏳ Verifying...</p>}
          {verifyHook.isSuccess && <p className="tx-status success">✓ Claim verified!</p>}
          {verifyHook.error && <p className="tx-status error">Could not verify — challenge period may not be over yet.</p>}
        </div>
      )}
    </div>
  );
}

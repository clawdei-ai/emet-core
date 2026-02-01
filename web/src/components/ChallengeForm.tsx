import { useState } from 'react';
import { useAccount } from 'wagmi';
import { parseUnits } from 'viem';
import { useInitiateChallenge, useApproveEMET, useTokenAllowance } from '../hooks/useProtocol';
import { CONTRACTS } from '../contracts/addresses';

interface ChallengeFormProps {
  claimId: bigint;
}

export function ChallengeForm({ claimId }: ChallengeFormProps) {
  const { address } = useAccount();
  const [counterEvidence, setCounterEvidence] = useState('');
  const [stakeAmount, setStakeAmount] = useState('100');
  const [tier, setTier] = useState(0); // 0=Minor, 1=Major, 2=Critical
  const [showForm, setShowForm] = useState(false);

  const challengeHook = useInitiateChallenge();
  const approveHook = useApproveEMET();
  const { data: allowance } = useTokenAllowance(address, CONTRACTS.EMETChallengeV3 || CONTRACTS.EMETChallenge);

  const stakeWei = stakeAmount ? parseUnits(stakeAmount, 18) : 0n;
  const needsApproval = allowance !== undefined && stakeWei > allowance;

  const handleSubmitChallenge = () => {
    if (!counterEvidence.trim()) return;

    if (needsApproval) {
      approveHook.approve(CONTRACTS.EMETChallengeV3 || CONTRACTS.EMETChallenge, stakeWei);
    } else {
      challengeHook.challenge(claimId, stakeAmount, counterEvidence, tier);
    }
  };

  if (!showForm) {
    return (
      <button
        className="btn btn-danger btn-full challenge-trigger-btn"
        onClick={() => setShowForm(true)}
      >
        ⚔️ Challenge This Claim
      </button>
    );
  }

  return (
    <div className="challenge-form">
      <div className="challenge-form-header">
        <h4>⚔️ Challenge This Claim</h4>
        <button className="btn btn-small btn-secondary" onClick={() => setShowForm(false)}>Cancel</button>
      </div>

      <p className="challenge-form-desc">
        You believe this claim is <strong>false</strong>. Provide counter-evidence and stake EMET to dispute it.
        If the challenge succeeds, you win the submitter's stake.
      </p>

      <div className="form-group">
        <label>Counter-Evidence</label>
        <textarea
          value={counterEvidence}
          onChange={(e) => setCounterEvidence(e.target.value)}
          placeholder="Explain why this claim is false. Include links to evidence that contradicts the claim..."
          rows={4}
          className="challenge-textarea"
        />
        <small>Provide clear reasoning and evidence. This helps other stakers evaluate the challenge.</small>
      </div>

      <div className="form-group">
        <label>Challenge Tier</label>
        <select value={tier} onChange={(e) => setTier(Number(e.target.value))}>
          <option value={0}>Minor (3 jurors, 48h, &lt;1,000 EMET)</option>
          <option value={1}>Major (7 jurors, 1 week, &lt;100,000 EMET)</option>
          <option value={2}>Critical (21 jurors, 2 weeks, ≥100,000 EMET)</option>
        </select>
        <small>Higher tiers involve more jurors and longer deliberation.</small>
      </div>

      <div className="form-group">
        <label>Challenge Stake (EMET)</label>
        <input
          type="number"
          value={stakeAmount}
          onChange={(e) => setStakeAmount(e.target.value)}
          min="100"
          step="1"
        />
        <small>Minimum 100 EMET. Higher stakes signal stronger conviction.</small>
      </div>

      <button
        className="btn btn-danger btn-full"
        onClick={handleSubmitChallenge}
        disabled={!counterEvidence.trim() || challengeHook.isPending || approveHook.isPending}
      >
        {needsApproval ? '🔓 Approve & Challenge' : '⚔️ Submit Challenge'}
      </button>

      {(approveHook.isPending || approveHook.isConfirming) && (
        <p className="tx-status">⏳ Approving tokens...</p>
      )}
      {(challengeHook.isPending || challengeHook.isConfirming) && (
        <p className="tx-status">⏳ Submitting challenge...</p>
      )}
      {challengeHook.isSuccess && (
        <p className="tx-status success">✓ Challenge submitted successfully!</p>
      )}
      {challengeHook.error && (
        <p className="tx-status error">Failed: {(challengeHook.error as Error).message?.slice(0, 100)}</p>
      )}
    </div>
  );
}

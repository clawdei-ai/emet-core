import { useState, useEffect } from 'react';
import { useAccount } from 'wagmi';
import { parseUnits } from 'viem';
import { useSubmitClaim, useApproveEMET, useMinimumStake, useTokenBalance, useTokenAllowance } from '../hooks/useProtocol';
import { CONTRACTS } from '../contracts/addresses';
import { formatEMET } from '../lib/format';

export function SubmitClaim() {
  const { address, isConnected } = useAccount();
  const [claimText, setClaimText] = useState('');
  const [evidenceURL, setEvidenceURL] = useState('');
  const [stakeAmount, setStakeAmount] = useState('100');
  const [step, setStep] = useState<'form' | 'approve' | 'submit' | 'done'>('form');

  const { data: minStake } = useMinimumStake();
  const { data: balance } = useTokenBalance(address);
  const { data: allowance, refetch: refetchAllowance } = useTokenAllowance(address, CONTRACTS.EMETRegistry);

  const { approve, isPending: approvePending, isConfirming: approveConfirming, isSuccess: approveSuccess } = useApproveEMET();
  const { submit, isPending: submitPending, isConfirming: submitConfirming, isSuccess: submitSuccess, hash } = useSubmitClaim();

  useEffect(() => {
    if (approveSuccess) {
      refetchAllowance().then(() => {
        setStep('submit');
        submit(claimText, evidenceURL, stakeAmount);
      });
    }
  }, [approveSuccess]);

  useEffect(() => {
    if (submitSuccess) setStep('done');
  }, [submitSuccess]);

  const stakeWei = stakeAmount ? parseUnits(stakeAmount, 18) : 0n;
  const needsApproval = allowance !== undefined && stakeWei > allowance;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!claimText || !evidenceURL || !stakeAmount) return;

    if (needsApproval) {
      setStep('approve');
      approve(CONTRACTS.EMETRegistry, stakeWei);
    } else {
      setStep('submit');
      submit(claimText, evidenceURL, stakeAmount);
    }
  };

  const handleProceedSubmit = () => {
    submit(claimText, evidenceURL, stakeAmount);
  };

  if (!isConnected) {
    return (
      <div className="page">
        <div className="card center-card">
          <h2>Submit a Claim</h2>
          <p>Connect your wallet to submit claims.</p>
        </div>
      </div>
    );
  }

  if (step === 'done') {
    return (
      <div className="page">
        <div className="card center-card">
          <div className="success-icon">✓</div>
          <h2>Claim Submitted!</h2>
          <p>Your claim has been submitted to the EMET Registry.</p>
          {hash && (
            <a href={`https://basescan.org/tx/${hash}`} target="_blank" rel="noreferrer" className="btn btn-secondary">
              View on BaseScan
            </a>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="page">
      <h1>Submit a Claim</h1>
      <p className="page-subtitle">Make a verifiable statement and stake EMET as collateral.</p>

      <form onSubmit={handleSubmit} className="form-card">
        <div className="form-group">
          <label>Claim Text</label>
          <textarea
            value={claimText}
            onChange={(e) => setClaimText(e.target.value)}
            placeholder="Enter your verifiable claim..."
            rows={4}
            required
          />
          <small>This text will be stored on-chain with its keccak256 hash.</small>
        </div>

        <div className="form-group">
          <label>Evidence URL</label>
          <input
            type="url"
            value={evidenceURL}
            onChange={(e) => setEvidenceURL(e.target.value)}
            placeholder="https://... or ipfs://..."
            required
          />
          <small>
            Link to evidence. <strong>Tip:</strong> Include the full claim text in your evidence document 
            so others can verify the hash. Create a <a href="https://gist.github.com" target="_blank" rel="noreferrer">GitHub Gist</a> or 
            upload JSON to IPFS with format: {`{"claim": "your text", "evidence": "..."}`}
          </small>
        </div>

        <div className="form-group">
          <label>Stake Amount (EMET)</label>
          <input
            type="number"
            value={stakeAmount}
            onChange={(e) => setStakeAmount(e.target.value)}
            min={minStake ? Number(minStake / 10n ** 18n) : 100}
            step="1"
            required
          />
          <small>
            Min: {minStake ? formatEMET(minStake) : '100'} EMET
            {balance !== undefined && ` · Balance: ${formatEMET(balance)} EMET`}
          </small>
        </div>

        {step === 'approve' ? (
          <div className="tx-status">
            {approvePending && <p>⏳ Approve EMET spend in your wallet...</p>}
            {approveConfirming && <p>⏳ Confirming approval...</p>}
            {approveSuccess && (
              <button type="button" className="btn btn-primary" onClick={handleProceedSubmit}>
                Submit Claim
              </button>
            )}
          </div>
        ) : step === 'submit' ? (
          <div className="tx-status">
            {submitPending && <p>⏳ Confirm transaction in your wallet...</p>}
            {submitConfirming && <p>⏳ Confirming on Base...</p>}
          </div>
        ) : (
          <button type="submit" className="btn btn-primary btn-full">
            {needsApproval ? 'Approve & Submit' : 'Submit Claim'}
          </button>
        )}
      </form>
    </div>
  );
}

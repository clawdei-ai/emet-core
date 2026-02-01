import { useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits, keccak256, toBytes } from 'viem';
import { CONTRACTS } from '../contracts/addresses';
import { EMETRegistryABI, EMETStakeABI, EMETChallengeABI, EMETReputationABI, EMETTokenABI } from '../contracts/abis';

// ============ Read Hooks ============

export function useClaimCount() {
  return useReadContract({
    address: CONTRACTS.EMETRegistry as `0x${string}`,
    abi: EMETRegistryABI,
    functionName: 'claimCount',
  });
}

export function useMinimumStake() {
  return useReadContract({
    address: CONTRACTS.EMETRegistry as `0x${string}`,
    abi: EMETRegistryABI,
    functionName: 'minimumStake',
  });
}

export function useChallengePeriod() {
  return useReadContract({
    address: CONTRACTS.EMETRegistry as `0x${string}`,
    abi: EMETRegistryABI,
    functionName: 'challengePeriod',
  });
}

export function useClaim(claimId: bigint) {
  return useReadContract({
    address: CONTRACTS.EMETRegistry as `0x${string}`,
    abi: EMETRegistryABI,
    functionName: 'getClaim',
    args: [claimId],
  });
}

export function useStakeTotals(claimId: bigint) {
  return useReadContract({
    address: CONTRACTS.EMETStake as `0x${string}`,
    abi: EMETStakeABI,
    functionName: 'getStakeTotals',
    args: [claimId],
  });
}

export function useUserStakes(claimId: bigint, staker: `0x${string}` | undefined) {
  return useReadContract({
    address: CONTRACTS.EMETStake as `0x${string}`,
    abi: EMETStakeABI,
    functionName: 'getUserStakes',
    args: staker ? [claimId, staker] : undefined,
    query: { enabled: !!staker },
  });
}

export function useChallenge(claimId: bigint) {
  return useReadContract({
    address: CONTRACTS.EMETChallenge as `0x${string}`,
    abi: EMETChallengeABI,
    functionName: 'getChallenge',
    args: [claimId],
  });
}

export function useCanResolve(claimId: bigint) {
  return useReadContract({
    address: CONTRACTS.EMETChallenge as `0x${string}`,
    abi: EMETChallengeABI,
    functionName: 'canResolve',
    args: [claimId],
  });
}

export function useReputation(account: `0x${string}` | undefined) {
  return useReadContract({
    address: CONTRACTS.EMETReputation as `0x${string}`,
    abi: EMETReputationABI,
    functionName: 'getReputation',
    args: account ? [account] : undefined,
    query: { enabled: !!account },
  });
}

export function useReputationTier(account: `0x${string}` | undefined) {
  return useReadContract({
    address: CONTRACTS.EMETReputation as `0x${string}`,
    abi: EMETReputationABI,
    functionName: 'getReputationTier',
    args: account ? [account] : undefined,
    query: { enabled: !!account },
  });
}

export function useTokenBalance(account: `0x${string}` | undefined) {
  return useReadContract({
    address: CONTRACTS.EMETToken as `0x${string}`,
    abi: EMETTokenABI,
    functionName: 'balanceOf',
    args: account ? [account] : undefined,
    query: { enabled: !!account },
  });
}

export function useTokenAllowance(owner: `0x${string}` | undefined, spender: string) {
  return useReadContract({
    address: CONTRACTS.EMETToken as `0x${string}`,
    abi: EMETTokenABI,
    functionName: 'allowance',
    args: owner ? [owner, spender as `0x${string}`] : undefined,
    query: { enabled: !!owner },
  });
}

// Batch-read multiple claims
export function useClaims(start: number, count: number) {
  const ids = Array.from({ length: count }, (_, i) => BigInt(start + i));
  return useReadContracts({
    contracts: ids.map((id) => ({
      address: CONTRACTS.EMETRegistry as `0x${string}`,
      abi: EMETRegistryABI,
      functionName: 'getClaim' as const,
      args: [id] as const,
    })),
  });
}

// ============ Write Hooks ============

export function useApproveEMET() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const approve = (spender: string, amount: bigint) => {
    writeContract({
      address: CONTRACTS.EMETToken as `0x${string}`,
      abi: EMETTokenABI,
      functionName: 'approve',
      args: [spender as `0x${string}`, amount],
    });
  };

  return { approve, isPending, isConfirming, isSuccess, error, hash };
}

export function useSubmitClaim() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const submit = (claimText: string, evidenceURI: string, stakeAmount: string) => {
    const claimHash = keccak256(toBytes(claimText));
    const stake = parseUnits(stakeAmount, 18);
    writeContract({
      address: CONTRACTS.EMETRegistry as `0x${string}`,
      abi: EMETRegistryABI,
      functionName: 'submitClaim',
      args: [claimHash, evidenceURI, stake],
    });
  };

  return { submit, isPending, isConfirming, isSuccess, error, hash };
}

export function useStakeFor() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const stakeFor = (claimId: bigint, amount: string) => {
    writeContract({
      address: CONTRACTS.EMETStake as `0x${string}`,
      abi: EMETStakeABI,
      functionName: 'stakeFor',
      args: [claimId, parseUnits(amount, 18)],
    });
  };

  return { stakeFor, isPending, isConfirming, isSuccess, error, hash };
}

export function useInitiateChallenge() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const challenge = (claimId: bigint, stake: string) => {
    writeContract({
      address: CONTRACTS.EMETChallenge as `0x${string}`,
      abi: EMETChallengeABI,
      functionName: 'initiateChallenge',
      args: [claimId, parseUnits(stake, 18)],
    });
  };

  return { challenge, isPending, isConfirming, isSuccess, error, hash };
}

export function useResolveChallenge() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const resolve = (claimId: bigint) => {
    writeContract({
      address: CONTRACTS.EMETChallenge as `0x${string}`,
      abi: EMETChallengeABI,
      functionName: 'resolveChallenge',
      args: [claimId],
    });
  };

  return { resolve, isPending, isConfirming, isSuccess, error, hash };
}

export function useVerifyUnchallenged() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const verify = (claimId: bigint) => {
    writeContract({
      address: CONTRACTS.EMETRegistry as `0x${string}`,
      abi: EMETRegistryABI,
      functionName: 'verifyUnchallenged',
      args: [claimId],
    });
  };

  return { verify, isPending, isConfirming, isSuccess, error, hash };
}

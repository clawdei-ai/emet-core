import { useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { useQueryClient } from '@tanstack/react-query';
import { parseUnits } from 'viem';
import { useEffect } from 'react';
import { CONTRACTS } from '../contracts/addresses';
import { EMETRegistryABI, EMETStakeABI, EMETChallengeABI, EMETReputationABI, EMETTokenABI } from '../contracts/abis';

// Refetch interval for live data (ms)
const LIVE = 6000;

// ============ Read Hooks ============

export function useClaimCount() {
  return useReadContract({
    address: CONTRACTS.EMETRegistry as `0x${string}`,
    abi: EMETRegistryABI,
    functionName: 'claimCount',
    query: { refetchInterval: LIVE },
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
    query: { refetchInterval: LIVE },
  });
}

export function useStakeTotals(claimId: bigint) {
  return useReadContract({
    address: CONTRACTS.EMETStake as `0x${string}`,
    abi: EMETStakeABI,
    functionName: 'getStakeTotals',
    args: [claimId],
    query: { refetchInterval: LIVE },
  });
}

export function useUserStakes(claimId: bigint, staker: `0x${string}` | undefined) {
  return useReadContract({
    address: CONTRACTS.EMETStake as `0x${string}`,
    abi: EMETStakeABI,
    functionName: 'getUserStakes',
    args: staker ? [claimId, staker] : undefined,
    query: { enabled: !!staker, refetchInterval: LIVE },
  });
}

export function useChallenge(claimId: bigint) {
  return useReadContract({
    address: CONTRACTS.EMETChallenge as `0x${string}`,
    abi: EMETChallengeABI,
    functionName: 'getChallenge',
    args: [claimId],
    query: { refetchInterval: LIVE },
  });
}

export function useCanResolve(claimId: bigint) {
  return useReadContract({
    address: CONTRACTS.EMETChallenge as `0x${string}`,
    abi: EMETChallengeABI,
    functionName: 'canResolve',
    args: [claimId],
    query: { refetchInterval: LIVE },
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
    query: { enabled: !!account, refetchInterval: LIVE },
  });
}

export function useTokenAllowance(owner: `0x${string}` | undefined, spender: string) {
  return useReadContract({
    address: CONTRACTS.EMETToken as `0x${string}`,
    abi: EMETTokenABI,
    functionName: 'allowance',
    args: owner ? [owner, spender as `0x${string}`] : undefined,
    query: { enabled: !!owner, refetchInterval: LIVE },
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
    query: { refetchInterval: LIVE },
  });
}

// ============ Invalidation Helper ============

function useInvalidateOnSuccess(hash: `0x${string}` | undefined, isSuccess: boolean) {
  const queryClient = useQueryClient();
  useEffect(() => {
    if (isSuccess && hash) {
      // Invalidate all wagmi read queries so everything refreshes
      queryClient.invalidateQueries();
    }
  }, [isSuccess, hash, queryClient]);
}

// ============ Write Hooks ============

export function useApproveEMET() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });
  useInvalidateOnSuccess(hash, isSuccess);

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
  useInvalidateOnSuccess(hash, isSuccess);

  const submit = (claimText: string, evidenceURI: string, stakeAmount: string) => {
    const stake = parseUnits(stakeAmount, 18);
    writeContract({
      address: CONTRACTS.EMETRegistry as `0x${string}`,
      abi: EMETRegistryABI,
      functionName: 'submitClaim',
      args: [claimText, evidenceURI, stake],
    });
  };

  return { submit, isPending, isConfirming, isSuccess, error, hash };
}

export function useStakeFor() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });
  useInvalidateOnSuccess(hash, isSuccess);

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
  useInvalidateOnSuccess(hash, isSuccess);

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
  useInvalidateOnSuccess(hash, isSuccess);

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
  useInvalidateOnSuccess(hash, isSuccess);

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

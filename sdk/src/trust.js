import { ethers } from 'ethers';
import { ABIS, ADDRESSES, DEFAULT_RPC } from './contracts.js';

export const Policy = Object.freeze({ LENIENT: 0, STANDARD: 1, STRICT: 2, CUSTOM: 3 });
export const PolicyName = Object.freeze({ 0: 'LENIENT', 1: 'STANDARD', 2: 'STRICT', 3: 'CUSTOM' });

export const Tier = Object.freeze({ UNRATED: 0, BRONZE: 1, SILVER: 2, GOLD: 3, PLATINUM: 4 });
export const TierName = Object.freeze({ 0: 'UNRATED', 1: 'BRONZE', 2: 'SILVER', 3: 'GOLD', 4: 'PLATINUM' });

export const RiskAppetite = Object.freeze({ UNKNOWN: 0, LOW: 1, MEDIUM: 2, HIGH: 3 });
export const RiskAppetiteName = Object.freeze({ 0: 'UNKNOWN', 1: 'LOW', 2: 'MEDIUM', 3: 'HIGH' });

const ZERO = '0x0000000000000000000000000000000000000000';

function asNumber(value) {
  return typeof value === 'bigint' ? Number(value) : Number(value ?? 0);
}

function asStringInt(value) {
  return (value ?? 0).toString();
}

export function normalizePolicy(policy = Policy.STANDARD) {
  if (typeof policy === 'string') {
    const key = policy.toUpperCase();
    if (Policy[key] === undefined) throw new Error(`Unknown EMET policy: ${policy}`);
    return Policy[key];
  }
  if (!Object.values(Policy).includes(policy)) throw new Error(`Unknown EMET policy: ${policy}`);
  return policy;
}

export function formatScore(score) {
  const s = normalizeScore(score);
  return `${s.tierName} ${s.trustScore}/1000 · ${(s.accuracyBps / 100).toFixed(1)}% accuracy · ${s.totalClaims} claims · rep ${s.reputation}`;
}

export function normalizeScore(score) {
  if (!score) return null;
  const tier = asNumber(score.tier);
  const riskAppetite = asNumber(score.riskAppetite);
  return {
    passesLenient: Boolean(score.passesLenient),
    passesStandard: Boolean(score.passesStandard),
    passesStrict: Boolean(score.passesStrict),
    accuracyBps: asNumber(score.accuracyBps),
    totalClaims: asNumber(score.totalClaims),
    correctClaims: asNumber(score.correctClaims),
    slashCount: asNumber(score.slashCount),
    avgStakeWei: asStringInt(score.avgStakeWei),
    riskAppetite,
    riskAppetiteName: RiskAppetiteName[riskAppetite] ?? 'UNKNOWN',
    reputation: asNumber(score.reputation),
    tier,
    tierName: TierName[tier] ?? 'UNRATED',
    trustScore: asNumber(score.trustScore)
  };
}

export function normalizeTrustResult(result, agent = undefined, policy = undefined) {
  if (!result) return null;
  return {
    agent,
    policy,
    policyName: policy === undefined ? undefined : PolicyName[policy],
    passes: Boolean(result.passes),
    accuracyBps: asNumber(result.accuracyBps),
    reputation: asNumber(result.reputation),
    totalClaims: asNumber(result.totalClaims),
    reason: result.reason ?? ''
  };
}

export class EMETTrust {
  constructor({ rpcUrl = DEFAULT_RPC, provider, signer, addresses = {}, contracts = {} } = {}) {
    this.provider = provider ?? signer?.provider ?? new ethers.JsonRpcProvider(rpcUrl);
    this.signer = signer;
    this.addresses = { ...ADDRESSES, ...addresses };

    const runner = signer ?? this.provider;
    this.trustGate = contracts.trustGate ?? new ethers.Contract(this.addresses.EMETTrustGate ?? ZERO, ABIS.EMETTrustGate, runner);
    this.scorecard = contracts.scorecard ?? new ethers.Contract(this.addresses.EMETScorecard ?? ZERO, ABIS.EMETScorecard, runner);
    this.agentProfile = contracts.agentProfile ?? new ethers.Contract(this.addresses.EMETAgentProfile ?? ZERO, ABIS.EMETAgentProfile, runner);
    this.reputation = contracts.reputation ?? new ethers.Contract(this.addresses.EMETReputation, ABIS.EMETReputation, runner);
  }

  async score(agent) {
    return normalizeScore(await this.scorecard.score(agent));
  }

  async peek(agent) {
    return normalizeScore(await this.scorecard.peek(agent));
  }

  async check(agent, policy = Policy.STANDARD) {
    const p = normalizePolicy(policy);
    const [passes, reason] = this.scorecard.check
      ? await this.scorecard.check(agent, p)
      : await this.trustGate.query(agent, p);
    return { agent, policy: p, policyName: PolicyName[p], passes: Boolean(passes), reason };
  }

  async evaluate(agent, policy = Policy.STANDARD) {
    const p = normalizePolicy(policy);
    return normalizeTrustResult(await this.trustGate.evaluate(agent, p), agent, p);
  }

  async evaluateBatch(agents, policy = Policy.STANDARD) {
    const p = normalizePolicy(policy);
    const results = await this.trustGate.evaluateBatch(agents, p);
    return results.map((result, i) => normalizeTrustResult(result, agents[i], p));
  }

  async filter(agents, policy = Policy.STANDARD) {
    const p = normalizePolicy(policy);
    return Array.from(await this.trustGate.filter(agents, p));
  }

  async tierOf(agent) {
    const tier = asNumber(await this.scorecard.tierOf(agent));
    return { tier, tierName: TierName[tier] ?? 'UNRATED' };
  }

  async trustScoreOf(agent) {
    return asNumber(await this.scorecard.trustScoreOf(agent));
  }

  async getProfile(agent) {
    const [profile, reputation, score] = await Promise.all([
      this.agentProfile.getProfile(agent),
      this.reputation.getReputation ? this.reputation.getReputation(agent) : this.reputation.reputation(agent),
      this.peek(agent)
    ]);

    return {
      agent,
      totalClaims: asNumber(profile.totalClaims),
      correctClaims: asNumber(profile.correctClaims),
      slashCount: asNumber(profile.slashCount),
      totalStakeWei: asStringInt(profile.totalStakeWei),
      avgStakeWei: asStringInt(profile.avgStakeWei),
      accuracyBps: asNumber(profile.accuracyBps),
      riskAppetite: asNumber(profile.riskAppetite),
      riskAppetiteName: RiskAppetiteName[asNumber(profile.riskAppetite)] ?? 'UNKNOWN',
      reputation: asNumber(reputation),
      score
    };
  }
}

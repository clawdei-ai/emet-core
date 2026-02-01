# EMET Protocol Economics Model

## Token Supply

| Allocation | Amount | % |
|------------|--------|---|
| Bootstrap Reserve | 400,000,000 | 40% |
| Protocol Treasury | 250,000,000 | 25% |
| Founding Agents | 150,000,000 | 15% |
| Human Oversight Council | 100,000,000 | 10% |
| Liquidity & Partnerships | 100,000,000 | 10% |
| **Total** | **1,000,000,000** | **100%** |

## Fee Structure (Proposed)

| Fee Type | Rate | Destination | Trigger |
|----------|------|-------------|---------|
| Challenge Resolution | 5% | Treasury | Losing party's stake |
| Progressive Staking | 1-10% | Treasury | Stakes >1% of pool |
| Claim Submission | 10 EMET | Treasury | Each new claim |
| Whistleblower Slash | 90% | Treasury | Verified collusion (10% to reporter) |
| Sybil Slash | 100% | Treasury | Banned sponsor's stake |

## Bootstrap Reserve Spend Plan

| Program | Amount | Duration | Monthly Burn |
|---------|--------|----------|--------------|
| Early Adopter Airdrop | 40M | 12 months | 3.3M |
| Developer Grants | 60M | 24 months | 2.5M |
| Jury Incentives | 20M | 24 months | 0.8M |
| Proof-of-Learning | 20M | 36 months | 0.6M |
| Strategic Reserve | 20M | held | 0 |
| **Unallocated** | **240M** | buffer | 0 |

**Total monthly burn (Year 1):** ~7.2M EMET

## Break-Even Model

### Assumptions (Conservative)
- Month 1-6: 100 claims/month, 10 challenges/month
- Month 7-12: 500 claims/month, 50 challenges/month
- Year 2: 2000 claims/month, 200 challenges/month
- Average stake per claim: 100 EMET
- Average challenge stake: 500 EMET

### Treasury Income Projection

**Year 1 (Months 1-6):**
```
Claims: 100 × 10 EMET = 1,000 EMET/month
Challenges: 10 × 500 × 5% = 250 EMET/month
Monthly income: ~1,250 EMET
```

**Year 1 (Months 7-12):**
```
Claims: 500 × 10 EMET = 5,000 EMET/month
Challenges: 50 × 500 × 5% = 12,500 EMET/month
Monthly income: ~17,500 EMET
```

**Year 2:**
```
Claims: 2000 × 10 EMET = 20,000 EMET/month
Challenges: 200 × 500 × 5% = 50,000 EMET/month
Progressive fees: ~10,000 EMET/month (estimate)
Monthly income: ~80,000 EMET
```

### Break-Even Analysis

| Period | Monthly Burn | Monthly Income | Net |
|--------|--------------|----------------|-----|
| Y1 H1 | 7,200,000 | 1,250 | -7,198,750 |
| Y1 H2 | 7,200,000 | 17,500 | -7,182,500 |
| Year 2 | 3,900,000* | 80,000 | -3,820,000 |
| Year 3 | 600,000** | 500,000*** | -100,000 |
| Year 4 | 600,000 | 2,000,000 | +1,400,000 ✅ |

*Airdrop complete, grants winding down
**Only proof-of-learning remaining
***10x activity growth

### Break-Even Point: ~Month 40 (mid Year 4)

At 10,000 claims/month and 1,000 challenges/month:
```
Claims: 10,000 × 10 = 100,000 EMET
Challenges: 1,000 × 500 × 5% = 250,000 EMET
Progressive: ~50,000 EMET
Monthly income: 400,000 EMET
Monthly expenses: ~600,000 EMET (ongoing rewards)
Gap: 200,000 EMET/month from Treasury principal
```

At 50,000 claims/month (network effect kicks in):
```
Monthly income: 2,000,000+ EMET
Monthly expenses: 600,000 EMET
Surplus: 1,400,000 EMET/month → buybacks or deeper liquidity
```

## Sustainability Levers

If growth is slower than projected:

1. **Reduce burn rate** - Smaller airdrops, slower grant deployment
2. **Increase fees** - Governance vote to raise challenge fee to 10%
3. **Add new fee sources** - API access, premium features, enterprise tiers
4. **Liquidity mining** - Use LP rewards to attract volume

If growth is faster than projected:

1. **Accelerate grants** - More developer incentives
2. **Reduce fees** - Lower barriers to entry
3. **Buybacks** - Treasury buys EMET from market, reducing supply
4. **Expand reserve** - Move surplus to Strategic Reserve

## Key Metrics to Track

| Metric | Target Y1 | Target Y2 | Break-even |
|--------|-----------|-----------|------------|
| Monthly claims | 500 | 2,000 | 10,000 |
| Monthly challenges | 50 | 200 | 1,000 |
| Active agents | 100 | 500 | 2,000 |
| Treasury balance | 250M | 200M | 150M+ growing |
| Bootstrap remaining | 320M | 200M | 150M |

## Risk Factors

1. **Low adoption** - Not enough agents use the protocol
   - Mitigation: Larger airdrops, partnership integrations

2. **Challenge avoidance** - Everyone stakes on obvious truths
   - Mitigation: Novelty scoring, no rewards for unchallenged claims

3. **Whale manipulation** - Rich actors game the system
   - Mitigation: Concentration limits, progressive fees

4. **Token price collapse** - EMET becomes worthless
   - Mitigation: Real utility, Treasury buybacks, fee burns

---

*Model updated: February 1, 2026*
*Version: 1.0*

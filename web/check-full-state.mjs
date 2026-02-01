import { createPublicClient, http } from 'viem';
import { base } from 'viem/chains';

const client = createPublicClient({
  chain: base,
  transport: http('https://mainnet.base.org')
});

// All contract addresses
const contracts = {
  Registry_v2: '0x266D8343463deE2920CBE97EfB72B4540E491DeC',
  Registry_v1: '0x69FC0F525F15DFB57e762cD2c570114433AFc6e2',
  JuryPool_v2: '0x018377D4e725703974A0087f8Ca8066c4aE8b045',
  JuryPool_v1: '0xDBa7434180e09c9b0857d5808a227E32E1c79bD8',
  ChallengeV3_v2: '0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9',
  ChallengeV3_v1: '0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332',
};

async function readAddress(contract, fn) {
  try {
    return await client.readContract({
      address: contract,
      abi: [{ name: fn, type: 'function', inputs: [], outputs: [{ type: 'address' }] }],
      functionName: fn
    });
  } catch (e) {
    return 'ERROR: ' + e.message.slice(0, 50);
  }
}

async function main() {
  console.log('=== Full Wiring Analysis ===\n');
  
  console.log('--- Registry v2 ---');
  console.log('challengeContract:', await readAddress(contracts.Registry_v2, 'challengeContract'));
  console.log('owner:', await readAddress(contracts.Registry_v2, 'owner'));
  
  console.log('\n--- Registry v1 ---');
  console.log('challengeContract:', await readAddress(contracts.Registry_v1, 'challengeContract'));
  
  console.log('\n--- JuryPool v2 ---');
  console.log('challengeContract:', await readAddress(contracts.JuryPool_v2, 'challengeContract'));
  console.log('deployer:', await readAddress(contracts.JuryPool_v2, 'deployer'));
  
  console.log('\n--- JuryPool v1 ---');
  console.log('challengeContract:', await readAddress(contracts.JuryPool_v1, 'challengeContract'));
  console.log('deployer:', await readAddress(contracts.JuryPool_v1, 'deployer'));
  
  console.log('\n--- ChallengeV3 v2 (current) ---');
  console.log('registry:', await readAddress(contracts.ChallengeV3_v2, 'registry'));
  console.log('treasury:', await readAddress(contracts.ChallengeV3_v2, 'treasury'));
  console.log('reputation:', await readAddress(contracts.ChallengeV3_v2, 'reputationContract'));
  console.log('juryPool:', await readAddress(contracts.ChallengeV3_v2, 'juryPool'));
  console.log('owner:', await readAddress(contracts.ChallengeV3_v2, 'owner'));
  
  console.log('\n--- ChallengeV3 v1 (legacy) ---');
  console.log('registry:', await readAddress(contracts.ChallengeV3_v1, 'registry'));
  console.log('juryPool:', await readAddress(contracts.ChallengeV3_v1, 'juryPool'));
  
  console.log('\n=== CRITICAL ISSUE ANALYSIS ===');
  console.log('');
  console.log('The problem:');
  console.log('1. ChallengeV3 v2 has IMMUTABLE reference to JuryPool v1');
  console.log('2. JuryPool v2 is wired to ChallengeV3 v2 (one-shot, cannot change)');
  console.log('3. Registry v2 is wired to ChallengeV3 v2 (one-shot, cannot change)');
  console.log('');
  console.log('Result: ChallengeV3 v2 calls JuryPool v1 but JuryPool v1 is NOT wired back');
  console.log('        The whole system is broken - jury selection will fail.');
  console.log('');
  console.log('To fix properly, we need to deploy fresh:');
  console.log('  - Registry v3');
  console.log('  - JuryPool v3'); 
  console.log('  - ChallengeV3 v3');
  console.log('And wire them correctly from the start.');
}

main().catch(console.error);

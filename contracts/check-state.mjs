import { createPublicClient, http } from 'viem';
import { base } from 'viem/chains';

const client = createPublicClient({
  chain: base,
  transport: http('https://mainnet.base.org')
});

const REGISTRY = '0x266D8343463deE2920CBE97EfB72B4540E491DeC';
const JURYPOOL_V2 = '0x018377D4e725703974A0087f8Ca8066c4aE8b045';
const CHALLENGEV3_V2 = '0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9';

async function main() {
  console.log('=== Checking On-Chain State ===\n');
  
  // Check Registry.challengeContract
  const registryChallengeContract = await client.readContract({
    address: REGISTRY,
    abi: [{ name: 'challengeContract', type: 'function', inputs: [], outputs: [{ type: 'address' }] }],
    functionName: 'challengeContract'
  });
  console.log(`Registry.challengeContract: ${registryChallengeContract}`);
  console.log(`  Expected (ChallengeV3 v2): ${CHALLENGEV3_V2}`);
  console.log(`  Is one-shot already set? ${registryChallengeContract !== '0x0000000000000000000000000000000000000000' ? 'YES ❌ BLOCKER' : 'NO ✅'}`);
  
  // Check JuryPool.challengeContract  
  const juryPoolChallengeContract = await client.readContract({
    address: JURYPOOL_V2,
    abi: [{ name: 'challengeContract', type: 'function', inputs: [], outputs: [{ type: 'address' }] }],
    functionName: 'challengeContract'
  });
  console.log(`\nJuryPool.challengeContract: ${juryPoolChallengeContract}`);
  console.log(`  Expected (ChallengeV3 v2): ${CHALLENGEV3_V2}`);
  console.log(`  Is one-shot already set? ${juryPoolChallengeContract !== '0x0000000000000000000000000000000000000000' ? 'YES ❌ BLOCKER' : 'NO ✅'}`);
  
  // Check ChallengeV3 v2's juryPool reference
  const challengeJuryPool = await client.readContract({
    address: CHALLENGEV3_V2,
    abi: [{ name: 'juryPool', type: 'function', inputs: [], outputs: [{ type: 'address' }] }],
    functionName: 'juryPool'
  });
  console.log(`\nChallengeV3_v2.juryPool: ${challengeJuryPool}`);
  console.log(`  JuryPool v1: 0xDBa7434180e09c9b0857d5808a227E32E1c79bD8`);
  console.log(`  JuryPool v2: ${JURYPOOL_V2}`);
  console.log(`  Points to NEW JuryPool v2? ${challengeJuryPool.toLowerCase() === JURYPOOL_V2.toLowerCase() ? 'YES ✅' : 'NO - points to OLD v1 ❌'}`);
  
  console.log('\n=== Summary ===');
  if (registryChallengeContract !== '0x0000000000000000000000000000000000000000') {
    console.log('❌ Registry.setChallengeContract is ONE-SHOT and ALREADY SET');
    console.log('   Cannot rewire Registry to new ChallengeV3 v3');
  }
  if (juryPoolChallengeContract !== '0x0000000000000000000000000000000000000000') {
    console.log('❌ JuryPool.setChallengeContract is ONE-SHOT and ALREADY SET');
    console.log('   Cannot rewire JuryPool v2 to new ChallengeV3 v3');
  }
}

main().catch(console.error);

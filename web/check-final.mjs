import { createPublicClient, http } from 'viem';
import { base } from 'viem/chains';

// Use alternative RPC
const client = createPublicClient({
  chain: base,
  transport: http('https://base.drpc.org')
});

const ChallengeV3_v2 = '0x697BAC4b1FCA88e12003C0ef3E03bdcbdE5d17D9';
const ChallengeV3_v1 = '0xfFd54b3B1D72BE8205D961566e1AD4134FBd5332';
const JuryPool_v1 = '0xDBa7434180e09c9b0857d5808a227E32E1c79bD8';

async function readAddress(contract, fn) {
  try {
    return await client.readContract({
      address: contract,
      abi: [{ name: fn, type: 'function', inputs: [], outputs: [{ type: 'address' }] }],
      functionName: fn
    });
  } catch (e) {
    return 'ERROR: ' + e.message.slice(0, 80);
  }
}

async function main() {
  console.log('=== ChallengeV3 v2 Complete State ===');
  console.log('juryPool:', await readAddress(ChallengeV3_v2, 'juryPool'));
  console.log('owner:', await readAddress(ChallengeV3_v2, 'owner'));
  
  console.log('\n=== ChallengeV3 v1 Complete State ===');
  console.log('registry:', await readAddress(ChallengeV3_v1, 'registry'));
  console.log('juryPool:', await readAddress(ChallengeV3_v1, 'juryPool'));
  
  console.log('\n=== JuryPool v1 State ===');
  console.log('challengeContract:', await readAddress(JuryPool_v1, 'challengeContract'));
}

main().catch(console.error);

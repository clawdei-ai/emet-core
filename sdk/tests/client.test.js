/**
 * EMET SDK Client Tests
 * 
 * Unit tests using Node's built-in test runner with mocks.
 */

import { describe, it, mock, beforeEach } from 'node:test';
import assert from 'node:assert';
import { EMETClient } from '../src/client.js';
import { ADDRESSES, ClaimStatus, ClaimStatusName } from '../src/contracts.js';

// Mock provider that returns predictable data
class MockProvider {
  constructor() {
    this.network = { chainId: 8453n, name: 'base' };
  }
  
  async getNetwork() {
    return this.network;
  }
  
  async getBlockNumber() {
    return 12345678;
  }
}

// Mock contract that tracks calls
class MockContract {
  constructor(address, abi, signerOrProvider) {
    this.address = address;
    this.abi = abi;
    this.calls = [];
  }
  
  _recordCall(method, args) {
    this.calls.push({ method, args });
  }
}

describe('EMETClient', () => {
  
  describe('constructor', () => {
    it('should create a read-only client without private key', () => {
      const client = new EMETClient();
      assert.ok(client.provider);
      assert.strictEqual(client.signer, null);
    });
    
    it('should create a signing client with private key', () => {
      // Use a test private key (not a real one!)
      const testKey = '0x' + '1'.repeat(64);
      const client = new EMETClient({ privateKey: testKey });
      assert.ok(client.provider);
      assert.ok(client.signer);
    });
    
    it('should use custom RPC URL', () => {
      const client = new EMETClient({ rpcUrl: 'https://custom.rpc.com' });
      assert.ok(client.provider);
    });
    
    it('should initialize all contract instances', () => {
      const client = new EMETClient();
      assert.ok(client.token);
      assert.ok(client.registry);
      assert.ok(client.stake);
      assert.ok(client.challenge);
    });
  });
  
  describe('getAddresses', () => {
    it('should return all contract addresses', () => {
      const client = new EMETClient();
      const addresses = client.getAddresses();
      
      assert.strictEqual(addresses.EMETToken, ADDRESSES.EMETToken);
      assert.strictEqual(addresses.EMETRegistry, ADDRESSES.EMETRegistry);
      assert.strictEqual(addresses.EMETStake, ADDRESSES.EMETStake);
      assert.strictEqual(addresses.EMETChallenge, ADDRESSES.EMETChallenge);
    });
  });
  
  describe('_requireSigner', () => {
    it('should throw when no signer available', () => {
      const client = new EMETClient();
      
      assert.throws(() => {
        client._requireSigner();
      }, /Signer required/);
    });
    
    it('should not throw when signer is available', () => {
      const testKey = '0x' + '1'.repeat(64);
      const client = new EMETClient({ privateKey: testKey });
      
      assert.doesNotThrow(() => {
        client._requireSigner();
      });
    });
  });
  
  describe('_parseStatusFilter', () => {
    it('should parse active status', () => {
      const client = new EMETClient();
      const filter = client._parseStatusFilter('active');
      assert.deepStrictEqual(filter, [ClaimStatus.ACTIVE]);
    });
    
    it('should parse verified status', () => {
      const client = new EMETClient();
      const filter = client._parseStatusFilter('verified');
      assert.deepStrictEqual(filter, [ClaimStatus.VERIFIED]);
    });
    
    it('should parse rejected status', () => {
      const client = new EMETClient();
      const filter = client._parseStatusFilter('rejected');
      assert.deepStrictEqual(filter, [ClaimStatus.REJECTED]);
    });
    
    it('should return null for unknown status', () => {
      const client = new EMETClient();
      const filter = client._parseStatusFilter('unknown');
      assert.strictEqual(filter, null);
    });
    
    it('should be case insensitive', () => {
      const client = new EMETClient();
      const filter = client._parseStatusFilter('ACTIVE');
      assert.deepStrictEqual(filter, [ClaimStatus.ACTIVE]);
    });
  });
  
  describe('getReputation', () => {
    it('should return a normalized reputation response', async () => {
      const client = new EMETClient();
      const rep = await client.getReputation('0x' + '1'.repeat(40));
      
      assert.strictEqual(typeof rep.available, 'boolean');
      assert.strictEqual(typeof rep.score, 'number');
      if (!rep.available) {
        assert.ok(rep.message.includes('not yet deployed') || rep.message.includes('unavailable'));
      }
    });
  });
  
});

describe('ClaimStatus', () => {
  it('should have correct status values', () => {
    assert.strictEqual(ClaimStatus.PENDING, 0);
    assert.strictEqual(ClaimStatus.ACTIVE, 1);
    assert.strictEqual(ClaimStatus.VERIFIED, 2);
    assert.strictEqual(ClaimStatus.REJECTED, 3);
    assert.strictEqual(ClaimStatus.DISPUTED, 4);
    assert.strictEqual(ClaimStatus.RESOLVED, 5);
  });
  
  it('should have correct status names', () => {
    assert.strictEqual(ClaimStatusName[0], 'Pending');
    assert.strictEqual(ClaimStatusName[1], 'Active');
    assert.strictEqual(ClaimStatusName[2], 'Verified');
    assert.strictEqual(ClaimStatusName[3], 'Rejected');
    assert.strictEqual(ClaimStatusName[4], 'Disputed');
    assert.strictEqual(ClaimStatusName[5], 'Resolved');
  });
});

describe('Contract Addresses', () => {
  it('should have valid Ethereum addresses', () => {
    const addressRegex = /^0x[a-fA-F0-9]{40}$/;
    
    assert.match(ADDRESSES.EMETToken, addressRegex);
    assert.match(ADDRESSES.EMETRegistry, addressRegex);
    assert.match(ADDRESSES.EMETStake, addressRegex);
    assert.match(ADDRESSES.EMETChallenge, addressRegex);
  });
  
  it('should have unique addresses', () => {
    const addresses = [
      ADDRESSES.EMETToken,
      ADDRESSES.EMETRegistry,
      ADDRESSES.EMETStake,
      ADDRESSES.EMETChallenge
    ];
    const unique = new Set(addresses);
    assert.strictEqual(unique.size, addresses.length);
  });
});

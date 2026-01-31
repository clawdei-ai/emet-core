#!/usr/bin/env node

/**
 * EMET Protocol CLI
 * 
 * Command-line interface for creating, signing, and verifying EMET claims.
 * Also supports Merkle tree operations for thread integrity proofs.
 */

const { Command } = require('commander');
const fs = require('fs');
const path = require('path');
const os = require('os');
const readline = require('readline');

// Import core modules
const { 
  createClaim, 
  signClaim, 
  verifyClaim, 
  hashClaim,
  generateKeyPair,
  ClaimType 
} = require('../core/claim');

const {
  buildTree,
  getProof,
  verifyProof,
  computeRoot
} = require('../core/merkle');

const program = new Command();

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Get the EMET keys directory path
 */
function getKeysDir() {
  return path.join(os.homedir(), '.emet', 'keys');
}

/**
 * Ensure the keys directory exists
 */
function ensureKeysDir() {
  const keysDir = getKeysDir();
  if (!fs.existsSync(keysDir)) {
    fs.mkdirSync(keysDir, { recursive: true, mode: 0o700 });
  }
  return keysDir;
}

/**
 * Load a key file
 */
function loadKey(keyPath) {
  const resolvedPath = keyPath.startsWith('~') 
    ? path.join(os.homedir(), keyPath.slice(1))
    : path.resolve(keyPath);
  
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`Key file not found: ${resolvedPath}`);
  }
  
  const keyData = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
  
  // Convert base64 to Uint8Array
  return {
    publicKey: new Uint8Array(Buffer.from(keyData.publicKey, 'base64')),
    secretKey: new Uint8Array(Buffer.from(keyData.secretKey, 'base64'))
  };
}

/**
 * Read JSON file
 */
function readJsonFile(filePath) {
  const resolvedPath = filePath.startsWith('~')
    ? path.join(os.homedir(), filePath.slice(1))
    : path.resolve(filePath);
  
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`File not found: ${resolvedPath}`);
  }
  
  return JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
}

/**
 * Write JSON file
 */
function writeJsonFile(filePath, data) {
  const resolvedPath = filePath.startsWith('~')
    ? path.join(os.homedir(), filePath.slice(1))
    : path.resolve(filePath);
  
  fs.writeFileSync(resolvedPath, JSON.stringify(data, null, 2));
}

/**
 * Get all claim JSON files from a directory
 */
function getClaimFiles(dirPath) {
  const resolvedPath = dirPath.startsWith('~')
    ? path.join(os.homedir(), dirPath.slice(1))
    : path.resolve(dirPath);
  
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`Directory not found: ${resolvedPath}`);
  }
  
  const files = fs.readdirSync(resolvedPath)
    .filter(f => f.endsWith('.json'))
    .map(f => path.join(resolvedPath, f));
  
  return files;
}

/**
 * Prompt for user input
 */
function prompt(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr
  });
  
  return new Promise(resolve => {
    rl.question(question, answer => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

// ============================================================================
// CLI Configuration
// ============================================================================

program
  .name('emet')
  .description('EMET Protocol CLI - Create, sign, and verify epistemic claims')
  .version('1.0.0');

// ============================================================================
// Init Command
// ============================================================================

program
  .command('init [dir]')
  .description('Initialize a new EMET project with directory structure, keypair, and config')
  .option('-f, --force', 'Overwrite existing .emet.json config')
  .action(async (dir, options) => {
    try {
      const projectDir = dir ? path.resolve(dir) : process.cwd();
      const configFile = path.join(projectDir, '.emet.json');

      // Check for existing project
      if (fs.existsSync(configFile) && !options.force) {
        console.error(`Error: .emet.json already exists in ${projectDir}`);
        console.error('Use --force to reinitialize.');
        process.exit(1);
      }

      // 1. Create directory structure
      const dirs = ['claims', 'keys', 'proofs'];
      if (!fs.existsSync(projectDir)) {
        fs.mkdirSync(projectDir, { recursive: true });
      }
      for (const d of dirs) {
        const dirPath = path.join(projectDir, d);
        if (!fs.existsSync(dirPath)) {
          fs.mkdirSync(dirPath, { recursive: true });
        }
      }

      // 2. Generate default keypair
      const keyFile = path.join(projectDir, 'keys', 'default.json');
      const keyPair = generateKeyPair();
      const keyData = {
        name: 'default',
        algorithm: 'ed25519',
        publicKey: Buffer.from(keyPair.publicKey).toString('base64'),
        secretKey: Buffer.from(keyPair.secretKey).toString('base64'),
        createdAt: new Date().toISOString()
      };
      fs.writeFileSync(keyFile, JSON.stringify(keyData, null, 2), { mode: 0o600 });

      // 3. Create .emet.json config
      const config = {
        version: '0.1.0',
        keyPath: './keys/default.json'
      };
      fs.writeFileSync(configFile, JSON.stringify(config, null, 2));

      // 4. Create README.md
      const readmePath = path.join(projectDir, 'README.md');
      if (!fs.existsSync(readmePath)) {
        const readme = `# EMET Project

This project uses the [EMET Protocol](https://github.com/clawdei-ai/emet-core) for epistemic claim management.

## Directory Structure

- \`claims/\` — Signed claim JSON files
- \`keys/\` — Ed25519 keypairs for signing
- \`proofs/\` — Merkle proofs for claim verification

## Quick Start

\`\`\`bash
# Create a signed claim
emet claim create "Your statement here" \\
  --confidence 0.9 \\
  --key ./keys/default.json > claims/my-claim.json

# Verify a claim
emet verify claims/my-claim.json

# Build a Merkle tree from all claims
emet tree build ./claims/ -o proofs/tree.json

# Generate a proof for a specific claim
emet tree prove claims/my-claim.json ./claims/ -o proofs/my-proof.json
\`\`\`

## Configuration

Project settings are stored in \`.emet.json\`:

- **version** — EMET config version
- **keyPath** — Default keypair path for signing

## Learn More

See the [EMET CLI documentation](https://github.com/clawdei-ai/emet-core/blob/main/cli/README.md) for the full command reference.
`;
        fs.writeFileSync(readmePath, readme);
      }

      // 5. Print success message
      const displayDir = dir || '.';
      console.log(`\n✓ EMET project initialized in ${displayDir}/\n`);
      console.log('  Created:');
      console.log('    claims/          — Store your signed claims here');
      console.log('    keys/default.json — Ed25519 signing keypair');
      console.log('    proofs/          — Store Merkle proofs here');
      console.log('    .emet.json       — Project configuration');
      if (!dir || !fs.existsSync(path.join(projectDir, 'README.md'))) {
        console.log('    README.md        — Usage instructions');
      }
      console.log(`\n  Public key: ${keyPair.publicKeyBase64}\n`);
      console.log('  Next steps:');
      console.log('    emet claim create "Your first claim" --key ./keys/default.json > claims/first.json');
      console.log('    emet verify claims/first.json');
      console.log('');

    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// ============================================================================
// Key Generation Command
// ============================================================================

program
  .command('keygen')
  .description('Generate a new Ed25519 keypair for signing claims')
  .option('-o, --output <name>', 'Key name (default: default)', 'default')
  .option('-f, --force', 'Overwrite existing key')
  .action(async (options) => {
    try {
      const keysDir = ensureKeysDir();
      const keyFile = path.join(keysDir, `${options.output}.json`);
      
      if (fs.existsSync(keyFile) && !options.force) {
        console.error(`Error: Key '${options.output}' already exists. Use --force to overwrite.`);
        process.exit(1);
      }
      
      const keyPair = generateKeyPair();
      
      const keyData = {
        name: options.output,
        algorithm: 'ed25519',
        publicKey: Buffer.from(keyPair.publicKey).toString('base64'),
        secretKey: Buffer.from(keyPair.secretKey).toString('base64'),
        createdAt: new Date().toISOString()
      };
      
      fs.writeFileSync(keyFile, JSON.stringify(keyData, null, 2), { mode: 0o600 });
      
      console.error(`Key saved to: ${keyFile}`);
      console.log(`Public key: ${keyPair.publicKeyBase64}`);
      
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// ============================================================================
// Claim Commands
// ============================================================================

const claimCmd = program
  .command('claim')
  .description('Claim management commands');

// Create claim
claimCmd
  .command('create <statement>')
  .description('Create a new EMET claim')
  .option('-c, --confidence <value>', 'Confidence level (0-1)', parseFloat)
  .option('-e, --evidence <url>', 'Evidence URL (repeatable)', (val, prev) => prev.concat([val]), [])
  .option('-k, --key <path>', 'Key file path for auto-signing')
  .option('-i, --issuer <uri>', 'Issuer URI', 'emet:agent:cli')
  .option('-t, --type <type>', 'Claim type (Assertion, Correction, Retraction, Endorsement, Dispute)', 'Assertion')
  .option('-d, --domain <domain>', 'Knowledge domain')
  .option('--subject <uri>', 'Subject URI')
  .option('--interactive', 'Interactive mode for additional fields')
  .action(async (statement, options) => {
    try {
      // Build claim parameters
      const params = {
        issuer: options.issuer,
        statement: statement,
        type: options.type
      };
      
      if (options.confidence !== undefined) {
        params.confidence = options.confidence;
      }
      
      if (options.evidence.length > 0) {
        params.evidence = options.evidence.map(url => ({ url, type: 'primary' }));
      }
      
      if (options.domain) {
        params.domain = options.domain;
      }
      
      if (options.subject) {
        params.subject = options.subject;
      }
      
      // Interactive mode
      if (options.interactive) {
        if (params.confidence === undefined) {
          const conf = await prompt('Confidence (0-1, default 0.5): ');
          if (conf) params.confidence = parseFloat(conf);
        }
        
        if (!params.domain) {
          const domain = await prompt('Domain (e.g., science, history): ');
          if (domain) params.domain = domain;
        }
        
        if (params.evidence.length === 0) {
          console.error('Add evidence URLs (empty line to finish):');
          while (true) {
            const url = await prompt('  URL: ');
            if (!url) break;
            params.evidence = params.evidence || [];
            params.evidence.push({ url, type: 'primary' });
          }
        }
        
        const caveats = [];
        console.error('Add caveats/limitations (empty line to finish):');
        while (true) {
          const caveat = await prompt('  Caveat: ');
          if (!caveat) break;
          caveats.push(caveat);
        }
        if (caveats.length > 0) {
          params.caveats = caveats;
        }
      }
      
      // Create the claim
      let claim = createClaim(params);
      
      // Auto-sign if key provided
      if (options.key) {
        const keyData = loadKey(options.key);
        claim = signClaim(claim, keyData.secretKey);
        console.error('Claim signed with provided key');
      }
      
      // Output claim JSON to stdout
      console.log(JSON.stringify(claim, null, 2));
      
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// Sign claim
claimCmd
  .command('sign <file>')
  .description('Sign an existing claim JSON file')
  .requiredOption('-k, --key <path>', 'Key file path')
  .option('-o, --output <file>', 'Output file (default: updates in place)')
  .action((file, options) => {
    try {
      const claim = readJsonFile(file);
      
      if (claim.signature) {
        console.error('Warning: Claim already has a signature. Re-signing...');
      }
      
      const keyData = loadKey(options.key);
      const signedClaim = signClaim(claim, keyData.secretKey);
      
      const outputPath = options.output || file;
      writeJsonFile(outputPath, signedClaim);
      
      console.error(`Signed claim written to: ${outputPath}`);
      console.error(`Signature: ${signedClaim.signature.signature.slice(0, 32)}...`);
      
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// ============================================================================
// Verify Command
// ============================================================================

program
  .command('verify <file>')
  .description('Verify a claim signature')
  .option('-p, --public-key <key>', 'Override public key (base64)')
  .action((file, options) => {
    try {
      const claim = readJsonFile(file);
      
      const verifyOptions = {};
      if (options.publicKey) {
        verifyOptions.publicKey = new Uint8Array(Buffer.from(options.publicKey, 'base64'));
      }
      
      const result = verifyClaim(claim, verifyOptions);
      
      console.log('Verification Result');
      console.log('==================');
      console.log(`Status: ${result.valid ? '✓ PASS' : '✗ FAIL'}`);
      console.log(`Claim ID: ${result.details.claimId}`);
      console.log(`Issuer: ${result.details.issuer}`);
      console.log(`Timestamp: ${result.details.timestamp}`);
      
      if (result.details.algorithm) {
        console.log(`Algorithm: ${result.details.algorithm}`);
      }
      if (result.details.signedAt) {
        console.log(`Signed at: ${result.details.signedAt}`);
      }
      
      if (result.error) {
        console.log(`Error: ${result.error}`);
      }
      
      // Check co-signatories if present
      if (claim.coSignatories && claim.coSignatories.length > 0) {
        console.log(`\nCo-signatories: ${claim.coSignatories.length}`);
        claim.coSignatories.forEach((cs, i) => {
          console.log(`  ${i + 1}. ${cs.agent} (${cs.endorsementType})`);
        });
      }
      
      process.exit(result.valid ? 0 : 1);
      
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// ============================================================================
// Tree Commands
// ============================================================================

const treeCmd = program
  .command('tree')
  .description('Merkle tree commands for thread integrity');

// Build tree
treeCmd
  .command('build <dir>')
  .description('Build Merkle tree from claim files in a directory')
  .option('-o, --output <file>', 'Save tree data to file')
  .action((dir, options) => {
    try {
      const files = getClaimFiles(dir);
      
      if (files.length === 0) {
        console.error(`No JSON files found in: ${dir}`);
        process.exit(1);
      }
      
      console.error(`Found ${files.length} claim file(s)`);
      
      // Load and hash all claims
      const claims = files.map(f => {
        const claim = readJsonFile(f);
        return {
          file: path.basename(f),
          claim,
          hash: hashClaim(claim)
        };
      });
      
      // Sort by claim ID for deterministic ordering
      claims.sort((a, b) => a.claim.id.localeCompare(b.claim.id));
      
      // Build tree from hashes
      const hashes = claims.map(c => c.hash);
      const tree = buildTree(hashes);
      
      const rootHash = tree.root.hash.toString('hex');
      
      console.error('\nClaims included:');
      claims.forEach((c, i) => {
        console.error(`  ${i}. ${c.file} (${c.hash.slice(0, 16)}...)`);
      });
      
      console.log(`\nMerkle Root: ${rootHash}`);
      console.error(`Tree depth: ${tree.depth}`);
      
      // Save tree data if requested
      if (options.output) {
        const treeData = {
          root: rootHash,
          size: tree.size,
          depth: tree.depth,
          leaves: claims.map((c, i) => ({
            index: i,
            file: c.file,
            claimId: c.claim.id,
            hash: c.hash
          })),
          createdAt: new Date().toISOString()
        };
        writeJsonFile(options.output, treeData);
        console.error(`Tree data saved to: ${options.output}`);
      }
      
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// Generate proof
treeCmd
  .command('prove <file> <dir>')
  .description('Generate Merkle proof that a claim belongs to the tree')
  .option('-o, --output <file>', 'Save proof to file')
  .action((file, dir, options) => {
    try {
      // Load the target claim
      const targetClaim = readJsonFile(file);
      const targetHash = hashClaim(targetClaim);
      
      // Load all claims from directory
      const files = getClaimFiles(dir);
      const claims = files.map(f => {
        const claim = readJsonFile(f);
        return {
          file: path.basename(f),
          claim,
          hash: hashClaim(claim)
        };
      });
      
      // Sort deterministically
      claims.sort((a, b) => a.claim.id.localeCompare(b.claim.id));
      
      // Find the target claim index
      const targetIndex = claims.findIndex(c => c.hash === targetHash);
      
      if (targetIndex === -1) {
        console.error('Error: Claim not found in the tree');
        console.error(`Target hash: ${targetHash}`);
        process.exit(1);
      }
      
      // Build tree
      const hashes = claims.map(c => c.hash);
      const tree = buildTree(hashes);
      
      // Generate proof
      const proof = getProof(tree, targetIndex);
      
      // Add metadata
      const proofData = {
        ...proof,
        claimId: targetClaim.id,
        claimFile: path.basename(file),
        generatedAt: new Date().toISOString()
      };
      
      if (options.output) {
        writeJsonFile(options.output, proofData);
        console.error(`Proof saved to: ${options.output}`);
      }
      
      console.log(JSON.stringify(proofData, null, 2));
      
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// Verify proof
treeCmd
  .command('verify <file> <proof> <root>')
  .description('Verify a Merkle proof')
  .action((file, proofFile, root) => {
    try {
      // Load claim and compute its hash
      const claim = readJsonFile(file);
      const claimHash = hashClaim(claim);
      
      // Load proof
      const proof = readJsonFile(proofFile);
      
      // Verify the leaf hash matches
      if (proof.leaf !== claimHash) {
        console.log('Verification Result');
        console.log('==================');
        console.log('Status: ✗ FAIL');
        console.log('Error: Claim hash does not match proof leaf');
        console.log(`Expected: ${proof.leaf}`);
        console.log(`Got: ${claimHash}`);
        process.exit(1);
      }
      
      // Verify proof against provided root
      const result = verifyProof(proof, { expectedRoot: root });
      
      console.log('Verification Result');
      console.log('==================');
      console.log(`Status: ${result.valid ? '✓ PASS' : '✗ FAIL'}`);
      console.log(`Claim ID: ${claim.id}`);
      console.log(`Leaf hash: ${claimHash.slice(0, 32)}...`);
      console.log(`Expected root: ${root}`);
      console.log(`Computed root: ${result.computedRoot}`);
      
      if (result.error) {
        console.log(`Error: ${result.error}`);
      }
      
      if (result.valid) {
        console.log('\n✓ Claim is verified to be part of the Merkle tree');
      }
      
      process.exit(result.valid ? 0 : 1);
      
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// ============================================================================
// Run CLI
// ============================================================================

program.parse();

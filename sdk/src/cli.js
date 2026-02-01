#!/usr/bin/env node

/**
 * EMET Protocol CLI
 * 
 * Command-line interface for interacting with EMET Protocol on Base.
 */

import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { EMETClient } from './client.js';
import { ADDRESSES, ClaimStatusName, ChallengeStatusName } from './contracts.js';

// ============================================================================
// Configuration
// ============================================================================

function getClient(options = {}) {
  const privateKey = options.privateKey || process.env.EMET_PRIVATE_KEY;
  const rpcUrl = options.rpcUrl || process.env.EMET_RPC_URL;
  
  return new EMETClient({ privateKey, rpcUrl });
}

function formatAddress(address) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function formatTimestamp(ts) {
  if (!ts) return 'N/A';
  return new Date(ts * 1000).toISOString();
}

// ============================================================================
// CLI Setup
// ============================================================================

const program = new Command();

program
  .name('emet')
  .description('EMET Protocol CLI - Interact with EMET on Base')
  .version('1.0.0')
  .option('--private-key <key>', 'Private key for signing transactions')
  .option('--rpc-url <url>', 'RPC URL (default: Base mainnet)');

// ============================================================================
// Status Command
// ============================================================================

program
  .command('status')
  .description('Show connection info and contract addresses')
  .action(async (options) => {
    const spinner = ora('Connecting to Base...').start();
    try {
      const client = getClient(program.opts());
      const network = await client.getNetworkInfo();
      const tokenInfo = await client.getTokenInfo();
      const claimCount = await client.getClaimCount();
      
      spinner.stop();
      
      console.log(chalk.bold('\n📊 EMET Protocol Status\n'));
      
      console.log(chalk.cyan('Network:'));
      console.log(`  Chain ID: ${network.chainId}`);
      console.log(`  Block: ${network.blockNumber}`);
      console.log(`  Base: ${network.isBase ? chalk.green('✓') : chalk.red('✗')}`);
      
      console.log(chalk.cyan('\nToken:'));
      console.log(`  Name: ${tokenInfo.name}`);
      console.log(`  Symbol: ${tokenInfo.symbol}`);
      console.log(`  Total Supply: ${tokenInfo.totalSupply}`);
      
      console.log(chalk.cyan('\nContracts:'));
      console.log(`  Token:     ${ADDRESSES.EMETToken}`);
      console.log(`  Registry:  ${ADDRESSES.EMETRegistry}`);
      console.log(`  Stake:     ${ADDRESSES.EMETStake}`);
      console.log(`  Challenge: ${ADDRESSES.EMETChallenge}`);
      
      console.log(chalk.cyan('\nStats:'));
      console.log(`  Total Claims: ${claimCount}`);
      
      if (client.signer) {
        const address = await client.getAddress();
        const balance = await client.getBalance();
        console.log(chalk.cyan('\nWallet:'));
        console.log(`  Address: ${address}`);
        console.log(`  Balance: ${balance.formatted} EMET`);
      }
      
      console.log('');
      
    } catch (err) {
      spinner.fail('Failed to connect');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// ============================================================================
// Balance Command
// ============================================================================

program
  .command('balance [address]')
  .description('Check EMET token balance')
  .action(async (address) => {
    const spinner = ora('Fetching balance...').start();
    try {
      const client = getClient(program.opts());
      const balance = await client.getBalance(address);
      
      spinner.stop();
      console.log(chalk.green(`Balance: ${balance.formatted} EMET`));
      
    } catch (err) {
      spinner.fail('Failed to fetch balance');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// ============================================================================
// Reputation Command
// ============================================================================

program
  .command('reputation [address]')
  .description('Check reputation score (stub - contract deploying)')
  .action(async (address) => {
    const spinner = ora('Fetching reputation...').start();
    try {
      const client = getClient(program.opts());
      const rep = await client.getReputation(address);
      
      spinner.stop();
      
      if (!rep.available) {
        console.log(chalk.yellow('⚠️  Reputation contract not yet deployed'));
        console.log(chalk.gray('Coming soon...'));
      } else {
        console.log(chalk.green(`Reputation: ${rep.score}`));
      }
      
    } catch (err) {
      spinner.fail('Failed to fetch reputation');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// ============================================================================
// Claim Commands
// ============================================================================

const claimCmd = program
  .command('claim')
  .description('Claim management commands');

// Submit claim
claimCmd
  .command('submit <text>')
  .description('Submit a new claim')
  .option('-s, --stake <amount>', 'Stake amount in EMET', '100')
  .option('-e, --evidence <url>', 'Evidence URL')
  .action(async (text, options) => {
    const spinner = ora('Submitting claim...').start();
    try {
      const client = getClient(program.opts());
      
      if (!client.signer) {
        spinner.fail('Private key required');
        console.error(chalk.red('Set EMET_PRIVATE_KEY or use --private-key'));
        process.exit(1);
      }
      
      spinner.text = 'Approving tokens...';
      const result = await client.submitClaim(text, {
        stake: options.stake,
        evidence: options.evidence || ''
      });
      
      spinner.succeed('Claim submitted!');
      console.log(chalk.cyan(`\nClaim ID: ${chalk.bold(result.claimId)}`));
      console.log(chalk.gray(`TX: ${result.txHash}`));
      
    } catch (err) {
      spinner.fail('Failed to submit claim');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// Get claim
claimCmd
  .command('get <claimId>')
  .description('Get claim details')
  .action(async (claimId) => {
    const spinner = ora('Fetching claim...').start();
    try {
      const client = getClient(program.opts());
      const claim = await client.getClaim(parseInt(claimId));
      
      spinner.stop();
      
      console.log(chalk.bold(`\n📋 Claim #${claim.id}\n`));
      console.log(`${chalk.cyan('Hash:')} ${claim.claimHash}`);
      console.log(`${chalk.cyan('Submitter:')} ${claim.submitter}`);
      console.log(`${chalk.cyan('Stake:')} ${claim.stake.formatted} EMET`);
      console.log(`${chalk.cyan('Status:')} ${claim.statusName}`);
      console.log(`${chalk.cyan('Evidence:')} ${claim.evidence || 'None'}`);
      console.log(`${chalk.cyan('Timestamp:')} ${formatTimestamp(claim.timestamp)}`);
      
      // Get stake info (may not exist for all claims)
      try {
        const stakeInfo = await client.getStakeInfo(parseInt(claimId));
        console.log(`${chalk.cyan('Stakes For:')} ${stakeInfo.totalFor} EMET`);
        console.log(`${chalk.cyan('Stakes Against:')} ${stakeInfo.totalAgainst} EMET`);
      } catch (e) {
        // Staking not available for this claim
      }
      
      // Check for challenges
      try {
        const challenge = await client.getChallenge(parseInt(claimId));
        if (challenge && challenge.challenger !== '0x0000000000000000000000000000000000000000') {
          console.log(chalk.yellow(`\n⚠️  Challenged by ${formatAddress(challenge.challenger)}`));
          console.log(`   Stake: ${challenge.stake.formatted} EMET`);
          console.log(`   Status: ${challenge.statusName}`);
        }
      } catch (e) {
        // No challenge info
      }
      
      console.log('');
      
    } catch (err) {
      spinner.fail('Failed to fetch claim');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// List claims
claimCmd
  .command('list')
  .description('List claims')
  .option('--status <status>', 'Filter by status: active, verified, rejected')
  .option('-l, --limit <n>', 'Max claims to show', '10')
  .action(async (options) => {
    const spinner = ora('Fetching claims...').start();
    try {
      const client = getClient(program.opts());
      const claims = await client.listClaims({
        status: options.status,
        limit: parseInt(options.limit)
      });
      
      spinner.stop();
      
      if (claims.length === 0) {
        console.log(chalk.yellow('No claims found'));
        return;
      }
      
      console.log(chalk.bold(`\n📋 Claims (${claims.length})\n`));
      
      for (const claim of claims) {
        const statusColor = {
          'Verified': chalk.green,
          'Rejected': chalk.red,
          'Active': chalk.blue,
          'Pending': chalk.yellow,
          'Disputed': chalk.magenta
        }[claim.statusName] || chalk.white;
        
        // Show hash if no content (on-chain only stores hash)
        const display = claim.content || claim.claimHash?.slice(0, 18) + '...';
        
        console.log(
          chalk.bold(`#${claim.id}`) + ' ' +
          statusColor(`[${claim.statusName}]`) + ' ' +
          display
        );
        console.log(chalk.gray(`   ${formatAddress(claim.submitter)} | ${claim.stake.formatted} EMET`));
      }
      
      console.log('');
      
    } catch (err) {
      spinner.fail('Failed to list claims');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// ============================================================================
// Stake Commands
// ============================================================================

const stakeCmd = program
  .command('stake')
  .description('Staking commands');

// Stake for
stakeCmd
  .command('for <claimId>')
  .description('Stake in support of a claim')
  .requiredOption('-a, --amount <amount>', 'Amount to stake')
  .action(async (claimId, options) => {
    const spinner = ora('Staking for claim...').start();
    try {
      const client = getClient(program.opts());
      
      if (!client.signer) {
        spinner.fail('Private key required');
        console.error(chalk.red('Set EMET_PRIVATE_KEY or use --private-key'));
        process.exit(1);
      }
      
      spinner.text = 'Approving tokens...';
      const result = await client.stakeFor(parseInt(claimId), options.amount);
      
      spinner.succeed(`Staked ${options.amount} EMET for claim #${claimId}`);
      console.log(chalk.gray(`TX: ${result.txHash}`));
      
    } catch (err) {
      spinner.fail('Failed to stake');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// Stake against
stakeCmd
  .command('against <claimId>')
  .description('Stake against a claim')
  .requiredOption('-a, --amount <amount>', 'Amount to stake')
  .action(async (claimId, options) => {
    const spinner = ora('Staking against claim...').start();
    try {
      const client = getClient(program.opts());
      
      if (!client.signer) {
        spinner.fail('Private key required');
        console.error(chalk.red('Set EMET_PRIVATE_KEY or use --private-key'));
        process.exit(1);
      }
      
      spinner.text = 'Approving tokens...';
      const result = await client.stakeAgainst(parseInt(claimId), options.amount);
      
      spinner.succeed(`Staked ${options.amount} EMET against claim #${claimId}`);
      console.log(chalk.gray(`TX: ${result.txHash}`));
      
    } catch (err) {
      spinner.fail('Failed to stake');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// ============================================================================
// Challenge Commands
// ============================================================================

const challengeCmd = program
  .command('challenge')
  .description('Challenge management');

// Create challenge
challengeCmd
  .command('create <claimId>')
  .description('Challenge a claim')
  .requiredOption('-e, --evidence <url>', 'Evidence URL')
  .requiredOption('-s, --stake <amount>', 'Stake amount')
  .action(async (claimId, options) => {
    const spinner = ora('Creating challenge...').start();
    try {
      const client = getClient(program.opts());
      
      if (!client.signer) {
        spinner.fail('Private key required');
        console.error(chalk.red('Set EMET_PRIVATE_KEY or use --private-key'));
        process.exit(1);
      }
      
      spinner.text = 'Approving tokens...';
      const result = await client.challenge(parseInt(claimId), {
        evidence: options.evidence,
        stake: options.stake
      });
      
      spinner.succeed(`Challenge created for claim #${claimId}`);
      console.log(chalk.gray(`TX: ${result.txHash}`));
      
    } catch (err) {
      spinner.fail('Failed to create challenge');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// Resolve challenge
challengeCmd
  .command('resolve <claimId>')
  .description('Resolve a challenge')
  .option('--success', 'Challenge succeeded (default)', true)
  .option('--failed', 'Challenge failed')
  .action(async (claimId, options) => {
    const spinner = ora('Resolving challenge...').start();
    try {
      const client = getClient(program.opts());
      
      if (!client.signer) {
        spinner.fail('Private key required');
        console.error(chalk.red('Set EMET_PRIVATE_KEY or use --private-key'));
        process.exit(1);
      }
      
      const canResolve = await client.canResolveChallenge(parseInt(claimId));
      if (!canResolve) {
        spinner.fail('Challenge cannot be resolved yet');
        process.exit(1);
      }
      
      const succeeded = !options.failed;
      const result = await client.resolveChallenge(parseInt(claimId), succeeded);
      
      spinner.succeed(`Challenge resolved (${succeeded ? 'succeeded' : 'failed'})`);
      console.log(chalk.gray(`TX: ${result.txHash}`));
      
    } catch (err) {
      spinner.fail('Failed to resolve challenge');
      console.error(chalk.red(`Error: ${err.message}`));
      process.exit(1);
    }
  });

// ============================================================================
// Parse and Run
// ============================================================================

program.parse();

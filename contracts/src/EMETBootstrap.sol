// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";
import {EMETRegistry} from "./EMETRegistry.sol";

/// @title EMETBootstrap - Bootstrap Reserve Distribution for EMET Protocol
/// @notice Manages the 400M EMET Bootstrap Reserve with vesting programs:
///   - earlyAdopterAirdrop: 40M EMET for first 1000 agents with 10+ verified claims
///   - developerGrants: 60M EMET, 25% per quarter vesting
///   - juryIncentives: 20M EMET for active jurors
///   - proofOfLearning: 20M EMET for capability proof rewards
///   - strategicReserve: 20M EMET, owner-only
///   - unallocated: 240M EMET buffer
///
/// @dev Requires funding with 400M EMET after deployment.
contract EMETBootstrap {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice EMET Registry for checking verified claims
    address public constant REGISTRY = 0x69FC0F525F15DFB57e762cD2c570114433AFc6e2;

    /// @notice Total Bootstrap Reserve
    uint256 public constant TOTAL_RESERVE = 400_000_000 ether;

    /// @notice Program allocations
    uint256 public constant EARLY_ADOPTER_ALLOCATION = 40_000_000 ether;
    uint256 public constant DEVELOPER_GRANTS_ALLOCATION = 60_000_000 ether;
    uint256 public constant JURY_INCENTIVES_ALLOCATION = 20_000_000 ether;
    uint256 public constant PROOF_OF_LEARNING_ALLOCATION = 20_000_000 ether;
    uint256 public constant STRATEGIC_RESERVE_ALLOCATION = 20_000_000 ether;
    uint256 public constant UNALLOCATED_BUFFER = 240_000_000 ether;

    /// @notice Airdrop parameters
    uint256 public constant AIRDROP_PER_AGENT = 40_000 ether; // 40M / 1000 agents
    uint256 public constant MAX_AIRDROP_RECIPIENTS = 1000;
    uint256 public constant MIN_VERIFIED_CLAIMS = 10;

    /// @notice Grant vesting parameters
    uint256 public constant QUARTERS_TOTAL = 4;
    uint256 public constant QUARTER_DURATION = 90 days;

    // ============ State ============

    /// @notice Contract owner
    address public owner;

    /// @notice Registry contract reference
    EMETRegistry public registry;

    /// @notice Deployment timestamp for vesting calculations
    uint256 public deploymentTime;

    /// @notice Program balances (remaining)
    uint256 public earlyAdopterRemaining;
    uint256 public developerGrantsRemaining;
    uint256 public juryIncentivesRemaining;
    uint256 public proofOfLearningRemaining;
    uint256 public strategicReserveRemaining;
    uint256 public unallocatedRemaining;

    /// @notice Airdrop tracking
    mapping(address => bool) public hasClaimedAirdrop;
    uint256 public airdropRecipientCount;

    /// @notice Developer grants vesting
    uint256 public grantsVestedQuarters;
    uint256 public grantsDisbursed;

    /// @notice Total disbursed per program
    uint256 public totalAirdropDisbursed;
    uint256 public totalGrantsDisbursed;
    uint256 public totalJuryDisbursed;
    uint256 public totalLearningDisbursed;
    uint256 public totalStrategicDisbursed;
    uint256 public totalUnallocatedDisbursed;

    // ============ Events ============

    event AirdropClaimed(address indexed agent, uint256 amount, uint256 verifiedClaims);
    event GrantDisbursed(address indexed recipient, uint256 amount, string reason);
    event JuryIncentivePaid(address indexed juror, uint256 amount);
    event LearningRewardPaid(address indexed learner, uint256 amount, string capability);
    event StrategicDisbursement(address indexed recipient, uint256 amount, string reason);
    event UnallocatedDisbursement(address indexed recipient, uint256 amount, string reason);
    event QuarterVested(uint256 indexed quarter, uint256 amountVested);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // ============ Errors ============

    error OnlyOwner();
    error ZeroAddress();
    error ZeroAmount();
    error AlreadyClaimed();
    error InsufficientVerifiedClaims(uint256 have, uint256 need);
    error AirdropCapReached();
    error InsufficientProgramBalance(string program, uint256 requested, uint256 available);
    error QuarterNotVested(uint256 currentQuarter, uint256 requestedQuarter);
    error TransferFailed();
    error InsufficientContractBalance(uint256 requested, uint256 available);

    // ============ Constructor ============

    /// @notice Deploy Bootstrap contract
    /// @param _registry Address of EMETRegistry (or address(0) to use constant)
    constructor(address _registry) {
        owner = msg.sender;
        deploymentTime = block.timestamp;

        // Use provided registry or default constant
        registry = _registry != address(0) ? EMETRegistry(_registry) : EMETRegistry(REGISTRY);

        // Initialize program balances
        earlyAdopterRemaining = EARLY_ADOPTER_ALLOCATION;
        developerGrantsRemaining = DEVELOPER_GRANTS_ALLOCATION;
        juryIncentivesRemaining = JURY_INCENTIVES_ALLOCATION;
        proofOfLearningRemaining = PROOF_OF_LEARNING_ALLOCATION;
        strategicReserveRemaining = STRATEGIC_RESERVE_ALLOCATION;
        unallocatedRemaining = UNALLOCATED_BUFFER;
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ============ Early Adopter Airdrop ============

    /// @notice Claim airdrop for agents with 10+ verified claims
    /// @dev First 1000 eligible agents can claim 40,000 EMET each
    function claimAirdrop() external {
        if (hasClaimedAirdrop[msg.sender]) revert AlreadyClaimed();
        if (airdropRecipientCount >= MAX_AIRDROP_RECIPIENTS) revert AirdropCapReached();

        // Check verified claims via Registry
        uint256 verifiedClaims = registry.getVerifiedClaimsCount(msg.sender);
        if (verifiedClaims < MIN_VERIFIED_CLAIMS) {
            revert InsufficientVerifiedClaims(verifiedClaims, MIN_VERIFIED_CLAIMS);
        }

        // Check contract has enough balance
        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < AIRDROP_PER_AGENT) {
            revert InsufficientContractBalance(AIRDROP_PER_AGENT, contractBalance);
        }

        // Check program allocation
        if (earlyAdopterRemaining < AIRDROP_PER_AGENT) {
            revert InsufficientProgramBalance("earlyAdopter", AIRDROP_PER_AGENT, earlyAdopterRemaining);
        }

        // Mark claimed before transfer (reentrancy protection)
        hasClaimedAirdrop[msg.sender] = true;
        airdropRecipientCount++;
        earlyAdopterRemaining -= AIRDROP_PER_AGENT;
        totalAirdropDisbursed += AIRDROP_PER_AGENT;

        // Transfer airdrop
        bool success = EMET.transfer(msg.sender, AIRDROP_PER_AGENT);
        if (!success) revert TransferFailed();

        emit AirdropClaimed(msg.sender, AIRDROP_PER_AGENT, verifiedClaims);
    }

    /// @notice Check if an address is eligible for airdrop
    /// @param account The address to check
    /// @return eligible True if can claim
    /// @return verifiedClaims Number of verified claims
    /// @return reason Reason if not eligible
    function checkAirdropEligibility(address account) 
        external 
        view 
        returns (bool eligible, uint256 verifiedClaims, string memory reason) 
    {
        if (hasClaimedAirdrop[account]) {
            return (false, 0, "Already claimed");
        }
        if (airdropRecipientCount >= MAX_AIRDROP_RECIPIENTS) {
            return (false, 0, "Airdrop cap reached");
        }
        
        verifiedClaims = registry.getVerifiedClaimsCount(account);
        if (verifiedClaims < MIN_VERIFIED_CLAIMS) {
            return (false, verifiedClaims, "Insufficient verified claims");
        }
        
        return (true, verifiedClaims, "Eligible");
    }

    // ============ Developer Grants (Vesting) ============

    /// @notice Disburse grant from vested allocation
    /// @dev 25% of 60M vests each quarter (15M per quarter)
    /// @param recipient Grant recipient address
    /// @param amount Amount to disburse
    /// @param reason Description of grant purpose
    function disburseGrant(address recipient, uint256 amount, string calldata reason) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Calculate vested amount
        uint256 currentQuarter = getCurrentQuarter();
        uint256 vestedTotal = (DEVELOPER_GRANTS_ALLOCATION * currentQuarter) / QUARTERS_TOTAL;
        uint256 availableToDisburse = vestedTotal - grantsDisbursed;

        if (amount > availableToDisburse) {
            revert InsufficientProgramBalance("developerGrants", amount, availableToDisburse);
        }

        // Check contract balance
        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientContractBalance(amount, contractBalance);
        }

        // Update state
        grantsDisbursed += amount;
        developerGrantsRemaining -= amount;
        totalGrantsDisbursed += amount;

        // Transfer
        bool success = EMET.transfer(recipient, amount);
        if (!success) revert TransferFailed();

        emit GrantDisbursed(recipient, amount, reason);
    }

    /// @notice Get current quarter since deployment (1-4, capped at 4)
    /// @return quarter Current quarter number
    function getCurrentQuarter() public view returns (uint256 quarter) {
        uint256 elapsed = block.timestamp - deploymentTime;
        quarter = (elapsed / QUARTER_DURATION) + 1;
        if (quarter > QUARTERS_TOTAL) quarter = QUARTERS_TOTAL;
    }

    /// @notice Get vested and available grant amounts
    /// @return vestedTotal Total amount vested so far
    /// @return disbursed Amount already disbursed
    /// @return available Amount available to disburse
    function getGrantVestingStatus() 
        external 
        view 
        returns (uint256 vestedTotal, uint256 disbursed, uint256 available) 
    {
        uint256 currentQuarter = getCurrentQuarter();
        vestedTotal = (DEVELOPER_GRANTS_ALLOCATION * currentQuarter) / QUARTERS_TOTAL;
        disbursed = grantsDisbursed;
        available = vestedTotal - disbursed;
    }

    // ============ Jury Incentives ============

    /// @notice Distribute jury incentive to active juror
    /// @param juror Juror address
    /// @param amount Incentive amount
    function distributeJuryIncentive(address juror, uint256 amount) external onlyOwner {
        if (juror == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (juryIncentivesRemaining < amount) {
            revert InsufficientProgramBalance("juryIncentives", amount, juryIncentivesRemaining);
        }

        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientContractBalance(amount, contractBalance);
        }

        juryIncentivesRemaining -= amount;
        totalJuryDisbursed += amount;

        bool success = EMET.transfer(juror, amount);
        if (!success) revert TransferFailed();

        emit JuryIncentivePaid(juror, amount);
    }

    /// @notice Batch distribute jury incentives
    /// @param jurors Array of juror addresses
    /// @param amounts Array of amounts (must match jurors length)
    function distributeJuryIncentiveBatch(
        address[] calldata jurors, 
        uint256[] calldata amounts
    ) external onlyOwner {
        require(jurors.length == amounts.length, "Length mismatch");
        
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        
        if (juryIncentivesRemaining < total) {
            revert InsufficientProgramBalance("juryIncentives", total, juryIncentivesRemaining);
        }

        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < total) {
            revert InsufficientContractBalance(total, contractBalance);
        }

        juryIncentivesRemaining -= total;
        totalJuryDisbursed += total;

        for (uint256 i = 0; i < jurors.length; i++) {
            if (jurors[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) continue;
            
            bool success = EMET.transfer(jurors[i], amounts[i]);
            if (!success) revert TransferFailed();
            
            emit JuryIncentivePaid(jurors[i], amounts[i]);
        }
    }

    // ============ Proof of Learning ============

    /// @notice Distribute proof of learning reward
    /// @param learner Learner address
    /// @param amount Reward amount
    /// @param capability Description of capability proven
    function distributeLearningReward(
        address learner, 
        uint256 amount, 
        string calldata capability
    ) external onlyOwner {
        if (learner == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (proofOfLearningRemaining < amount) {
            revert InsufficientProgramBalance("proofOfLearning", amount, proofOfLearningRemaining);
        }

        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientContractBalance(amount, contractBalance);
        }

        proofOfLearningRemaining -= amount;
        totalLearningDisbursed += amount;

        bool success = EMET.transfer(learner, amount);
        if (!success) revert TransferFailed();

        emit LearningRewardPaid(learner, amount, capability);
    }

    // ============ Strategic Reserve ============

    /// @notice Disburse from strategic reserve (owner only, no vesting)
    /// @param recipient Recipient address
    /// @param amount Amount to disburse
    /// @param reason Reason for disbursement
    function disburseStrategic(
        address recipient, 
        uint256 amount, 
        string calldata reason
    ) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (strategicReserveRemaining < amount) {
            revert InsufficientProgramBalance("strategicReserve", amount, strategicReserveRemaining);
        }

        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientContractBalance(amount, contractBalance);
        }

        strategicReserveRemaining -= amount;
        totalStrategicDisbursed += amount;

        bool success = EMET.transfer(recipient, amount);
        if (!success) revert TransferFailed();

        emit StrategicDisbursement(recipient, amount, reason);
    }

    // ============ Unallocated Buffer ============

    /// @notice Disburse from unallocated buffer (owner only)
    /// @param recipient Recipient address
    /// @param amount Amount to disburse
    /// @param reason Reason for disbursement
    function disburseUnallocated(
        address recipient, 
        uint256 amount, 
        string calldata reason
    ) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (unallocatedRemaining < amount) {
            revert InsufficientProgramBalance("unallocated", amount, unallocatedRemaining);
        }

        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientContractBalance(amount, contractBalance);
        }

        unallocatedRemaining -= amount;
        totalUnallocatedDisbursed += amount;

        bool success = EMET.transfer(recipient, amount);
        if (!success) revert TransferFailed();

        emit UnallocatedDisbursement(recipient, amount, reason);
    }

    // ============ Owner Functions ============

    /// @notice Transfer ownership
    /// @param newOwner New owner address
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /// @notice Update registry address (in case of migration)
    /// @param _registry New registry address
    function setRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert ZeroAddress();
        address oldRegistry = address(registry);
        registry = EMETRegistry(_registry);
        emit RegistryUpdated(oldRegistry, _registry);
    }

    // ============ View Functions ============

    /// @notice Get all program balances
    function getProgramBalances() 
        external 
        view 
        returns (
            uint256 earlyAdopter,
            uint256 developerGrants,
            uint256 juryIncentives,
            uint256 proofOfLearning,
            uint256 strategicReserve,
            uint256 unallocated
        ) 
    {
        return (
            earlyAdopterRemaining,
            developerGrantsRemaining,
            juryIncentivesRemaining,
            proofOfLearningRemaining,
            strategicReserveRemaining,
            unallocatedRemaining
        );
    }

    /// @notice Get total disbursements per program
    function getTotalDisbursements()
        external
        view
        returns (
            uint256 airdrop,
            uint256 grants,
            uint256 jury,
            uint256 learning,
            uint256 strategic,
            uint256 unallocatedDisbursed
        )
    {
        return (
            totalAirdropDisbursed,
            totalGrantsDisbursed,
            totalJuryDisbursed,
            totalLearningDisbursed,
            totalStrategicDisbursed,
            totalUnallocatedDisbursed
        );
    }

    /// @notice Get airdrop statistics
    function getAirdropStats()
        external
        view
        returns (
            uint256 recipientCount,
            uint256 maxRecipients,
            uint256 amountPerAgent,
            uint256 remaining
        )
    {
        return (
            airdropRecipientCount,
            MAX_AIRDROP_RECIPIENTS,
            AIRDROP_PER_AGENT,
            earlyAdopterRemaining
        );
    }

    /// @notice Get contract's current EMET balance
    function balance() external view returns (uint256) {
        return EMET.balanceOf(address(this));
    }
}

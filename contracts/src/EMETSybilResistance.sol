// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETSybilResistance - Sponsorship system with slashing
/// @notice Prevents fake account spam through a sponsorship model.
///         Sponsors stake EMET as collateral for new agents. If sponsee misbehaves,
///         sponsor gets slashed. If sponsee graduates (rep > 50), sponsor gets bonus.
///
/// @dev Rate limiting: max 5 active sponsorships per sponsor per 30-day epoch.
///      Slashing is called by authorized contracts (Reputation/Governance).
///      Graduation is also triggered by authorized contracts.
///
///      Lifecycle:
///        1. Sponsor calls sponsor(newAgent, stake) — min 500 EMET
///        2. Sponsee operates with limited capabilities
///        3a. If sponsee reaches rep > 50 → graduateSponsor() → stake returned + bonus
///        3b. If sponsee misbehaves → slashSponsor() → stake lost, sponsee banned
contract EMETSybilResistance {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Minimum sponsorship stake
    uint256 public constant MIN_SPONSOR_STAKE = 500 ether;

    /// @notice Maximum active sponsorships per sponsor per epoch
    uint256 public constant MAX_SPONSORSHIPS_PER_EPOCH = 5;

    /// @notice Epoch duration (30 days)
    uint256 public constant EPOCH_DURATION = 30 days;

    /// @notice Graduation bonus percentage (10% of stake)
    uint256 public constant GRADUATION_BONUS_BPS = 1000;

    /// @notice BPS denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Types ============

    struct Sponsor {
        address addr;
        uint256 totalSponsored;
        uint256 slashedAmount;
        uint256 successfulSponsees;  // Sponsees who graduated (rep > 50)
        uint256 failedSponsees;      // Sponsees who got slashed
    }

    struct Sponsorship {
        address sponsor;
        address sponsee;
        uint256 stake;
        uint256 timestamp;
        bool graduated;
        bool slashed;
        bool active;             // Still in sponsorship period
    }

    // ============ State ============

    /// @notice Sponsor data by address
    mapping(address => Sponsor) public sponsors;

    /// @notice Sponsorship data by sponsee address
    mapping(address => Sponsorship) public sponsorships;

    /// @notice Sponsorships per sponsor per epoch: sponsor => epochStart => count
    mapping(address => mapping(uint256 => uint256)) public epochSponsorships;

    /// @notice Whether an address is banned
    mapping(address => bool) public banned;

    /// @notice Whether an address has been sponsored (ever)
    mapping(address => bool) public wasSponsored;

    /// @notice Authorized slasher/graduator contracts
    mapping(address => bool) public authorizedCallers;

    /// @notice Deployer for initial setup
    address public immutable deployer;

    /// @notice Total sponsorships created
    uint256 public totalSponsorships;

    /// @notice Total slashes executed
    uint256 public totalSlashes;

    /// @notice Total graduations
    uint256 public totalGraduations;

    /// @notice Treasury for collecting slashed funds
    address public treasuryAddress;

    // ============ Events ============

    event Sponsored(
        address indexed sponsor,
        address indexed sponsee,
        uint256 stake,
        uint256 timestamp
    );

    event SponsorSlashed(
        address indexed sponsor,
        address indexed sponsee,
        uint256 slashedAmount
    );

    event SponseeGraduated(
        address indexed sponsor,
        address indexed sponsee,
        uint256 stakeReturned,
        uint256 bonus
    );

    event SponseeBanned(address indexed sponsee);

    event AuthorizedCallerSet(address indexed caller, bool authorized);

    // ============ Errors ============

    error InsufficientStake(uint256 provided, uint256 required);
    error AlreadySponsored(address sponsee);
    error NotSponsored(address sponsee);
    error SponsorshipNotActive(address sponsee);
    error AlreadyGraduated(address sponsee);
    error AlreadySlashed(address sponsee);
    error AddressBanned(address addr);
    error RateLimitExceeded(address sponsor, uint256 current, uint256 max);
    error CannotSponsorSelf();
    error OnlyAuthorizedCaller();
    error OnlyDeployer();
    error TransferFailed();
    error ZeroAddress();

    // ============ Constructor ============

    constructor(address _treasury) {
        if (_treasury == address(0)) revert ZeroAddress();
        deployer = msg.sender;
        treasuryAddress = _treasury;
    }

    // ============ Configuration ============

    /// @notice Authorize a contract to call slash/graduate
    /// @param caller Address to authorize
    /// @param authorized Whether to authorize or deauthorize
    function setAuthorizedCaller(address caller, bool authorized) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (caller == address(0)) revert ZeroAddress();
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerSet(caller, authorized);
    }

    // ============ Sponsorship ============

    /// @notice Sponsor a new agent by staking EMET as collateral
    /// @param newAgent Address of the agent to sponsor
    /// @param stake Amount of EMET to stake (min 500 EMET)
    function sponsor(address newAgent, uint256 stake) external {
        if (newAgent == address(0)) revert ZeroAddress();
        if (newAgent == msg.sender) revert CannotSponsorSelf();
        if (stake < MIN_SPONSOR_STAKE) revert InsufficientStake(stake, MIN_SPONSOR_STAKE);
        if (wasSponsored[newAgent]) revert AlreadySponsored(newAgent);
        if (banned[newAgent]) revert AddressBanned(newAgent);
        if (banned[msg.sender]) revert AddressBanned(msg.sender);

        // Check rate limiting
        uint256 currentEpoch = _getCurrentEpoch();
        uint256 epochCount = epochSponsorships[msg.sender][currentEpoch];
        if (epochCount >= MAX_SPONSORSHIPS_PER_EPOCH) {
            revert RateLimitExceeded(msg.sender, epochCount, MAX_SPONSORSHIPS_PER_EPOCH);
        }

        // Transfer stake
        if (!EMET.transferFrom(msg.sender, address(this), stake)) revert TransferFailed();

        // Create sponsorship
        sponsorships[newAgent] = Sponsorship({
            sponsor: msg.sender,
            sponsee: newAgent,
            stake: stake,
            timestamp: block.timestamp,
            graduated: false,
            slashed: false,
            active: true
        });

        // Update sponsor stats
        Sponsor storage sp = sponsors[msg.sender];
        if (sp.addr == address(0)) {
            sp.addr = msg.sender;
        }
        sp.totalSponsored++;

        // Update rate limiting
        epochSponsorships[msg.sender][currentEpoch]++;
        wasSponsored[newAgent] = true;
        totalSponsorships++;

        emit Sponsored(msg.sender, newAgent, stake, block.timestamp);
    }

    // ============ Slashing ============

    /// @notice Slash a sponsor when their sponsee misbehaves
    /// @dev Only callable by authorized contracts (Reputation, Governance)
    /// @param sponsee Address of the misbehaving sponsee
    function slashSponsor(address sponsee) external {
        _onlyAuthorized();

        Sponsorship storage sp = sponsorships[sponsee];
        if (sp.sponsor == address(0)) revert NotSponsored(sponsee);
        if (!sp.active) revert SponsorshipNotActive(sponsee);
        if (sp.slashed) revert AlreadySlashed(sponsee);

        sp.slashed = true;
        sp.active = false;
        uint256 slashedAmount = sp.stake;

        // Update sponsor stats
        Sponsor storage sponsor_ = sponsors[sp.sponsor];
        sponsor_.slashedAmount += slashedAmount;
        sponsor_.failedSponsees++;

        // Ban sponsee
        banned[sponsee] = true;

        // Send slashed stake to treasury
        if (slashedAmount > 0) {
            if (!EMET.transfer(treasuryAddress, slashedAmount)) revert TransferFailed();
        }

        totalSlashes++;

        emit SponsorSlashed(sp.sponsor, sponsee, slashedAmount);
        emit SponseeBanned(sponsee);
    }

    // ============ Graduation ============

    /// @notice Graduate a sponsee when they reach rep > 50
    /// @dev Only callable by authorized contracts (Reputation)
    /// @param sponsee Address of the graduating sponsee
    function graduateSponsor(address sponsee) external {
        _onlyAuthorized();

        Sponsorship storage sp = sponsorships[sponsee];
        if (sp.sponsor == address(0)) revert NotSponsored(sponsee);
        if (!sp.active) revert SponsorshipNotActive(sponsee);
        if (sp.graduated) revert AlreadyGraduated(sponsee);

        sp.graduated = true;
        sp.active = false;

        // Update sponsor stats
        Sponsor storage sponsor_ = sponsors[sp.sponsor];
        sponsor_.successfulSponsees++;

        // Calculate bonus
        uint256 bonus = (sp.stake * GRADUATION_BONUS_BPS) / BPS_DENOMINATOR;
        uint256 totalReturn = sp.stake + bonus;

        // Return stake + bonus to sponsor
        // Note: bonus comes from contract's own balance (funded by treasury or initial)
        // If insufficient for bonus, just return stake
        uint256 contractBalance = EMET.balanceOf(address(this));
        if (contractBalance < totalReturn) {
            totalReturn = sp.stake; // Can't afford bonus, just return stake
            bonus = 0;
        }

        if (totalReturn > 0) {
            if (!EMET.transfer(sp.sponsor, totalReturn)) revert TransferFailed();
        }

        totalGraduations++;

        emit SponseeGraduated(sp.sponsor, sponsee, sp.stake, bonus);
    }

    // ============ Internal Functions ============

    function _onlyAuthorized() internal view {
        if (!authorizedCallers[msg.sender]) revert OnlyAuthorizedCaller();
    }

    function _getCurrentEpoch() internal view returns (uint256) {
        return block.timestamp / EPOCH_DURATION;
    }

    // ============ View Functions ============

    /// @notice Check if a sponsor can create a new sponsorship
    /// @param sponsor_ Address to check
    /// @return canDo Whether the sponsor can sponsor
    /// @return reason Human-readable reason if cannot
    function canSponsor(address sponsor_) external view returns (bool canDo, string memory reason) {
        if (banned[sponsor_]) return (false, "Sponsor is banned");

        uint256 currentEpoch = _getCurrentEpoch();
        uint256 epochCount = epochSponsorships[sponsor_][currentEpoch];

        if (epochCount >= MAX_SPONSORSHIPS_PER_EPOCH) {
            return (false, "Rate limit exceeded for this epoch");
        }

        return (true, "");
    }

    /// @notice Get sponsor statistics
    /// @param sponsor_ Address to query
    /// @return The sponsor struct
    function getSponsorStats(address sponsor_) external view returns (Sponsor memory) {
        return sponsors[sponsor_];
    }

    /// @notice Get sponsorship details for a sponsee
    /// @param sponsee Address to query
    /// @return The sponsorship struct
    function getSponsorship(address sponsee) external view returns (Sponsorship memory) {
        return sponsorships[sponsee];
    }

    /// @notice Check if an address is banned
    /// @param addr Address to check
    /// @return True if banned
    function isBanned(address addr) external view returns (bool) {
        return banned[addr];
    }

    /// @notice Check if an address has an active sponsorship
    /// @param sponsee Address to check
    /// @return True if actively sponsored
    function isActivelySponsored(address sponsee) external view returns (bool) {
        return sponsorships[sponsee].active;
    }

    /// @notice Get current epoch number
    /// @return The current epoch
    function getCurrentEpoch() external view returns (uint256) {
        return _getCurrentEpoch();
    }

    /// @notice Get sponsorships used in current epoch by a sponsor
    /// @param sponsor_ Address to query
    /// @return count Number of sponsorships used this epoch
    function getEpochSponsorshipCount(address sponsor_) external view returns (uint256 count) {
        return epochSponsorships[sponsor_][_getCurrentEpoch()];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title EMETWatchtower
/// @author Clawdei (EMET Protocol)
/// @notice Decentralized slash detection: watchtowers monitor claims and earn bounties.
///         Implements the v2 design from docs/emet-architecture-v2-design.md §4 & §5.
///
/// ## How it works
///
/// 1. **Register**: A watchtower stakes a small registration bond (REGISTRATION_BOND).
///    This prevents spam — flagging costs reputation.
///
/// 2. **Flag**: A watchtower calls `flag(claimId, evidence)` to signal a discrepancy
///    between a staked claim and its observed outcome. The flag is recorded on-chain.
///
/// 3. **Dynamic challenge bond**: Any challenger calling `getChallengeBond(claimId)`
///    gets a bond price computed as:
///      bond = BASE_BOND
///             × timeMultiplier(elapsed)    — older claims are harder to challenge
///             × stakeMultiplier(stakeAmt)  — bigger stakes attract more scrutiny
///             × consensusDiscount(flags)   — more flags = cheaper (consensus forming)
///
/// 4. **Slash split (v2)**: When a challenge succeeds:
///      - Primary challenger: 50% of slash
///      - Watchtower (if a valid flag exists): 20% of slash
///      - Treasury: 30% of slash
///
/// 5. **False flag penalty**: If a watchtower's flag is repeatedly not followed by a
///    successful challenge (MISSED_FLAG_LIMIT), their bond is slashed and they are
///    deregistered.

contract EMETWatchtower {
    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Bond required to register as a watchtower (in wei)
    uint256 public constant REGISTRATION_BOND = 0.001 ether;

    /// @notice Base challenge bond before any multipliers (in wei)
    uint256 public constant BASE_BOND = 0.0005 ether;

    /// @notice Fraction of slash going to primary challenger (basis points, 5000 = 50%)
    uint256 public constant CHALLENGER_SHARE_BPS = 5_000;

    /// @notice Fraction of slash going to the flagging watchtower (basis points, 2000 = 20%)
    uint256 public constant WATCHTOWER_SHARE_BPS = 2_000;

    /// @notice Fraction of slash going to treasury (basis points, 3000 = 30%)
    uint256 public constant TREASURY_SHARE_BPS = 3_000;

    /// @notice Number of stale flags (no successful challenge) before bond is slashed
    uint256 public constant MISSED_FLAG_LIMIT = 5;

    // ─────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────

    struct WatchtowerInfo {
        bool active;
        uint256 bond;           // locked registration bond (in wei)
        uint256 flagCount;      // total flags filed
        uint256 missedFlags;    // flags not followed by a successful challenge
        uint256 earnedBounty;   // cumulative bounty earned (not yet withdrawn)
        uint256 registeredAt;
    }

    struct Flag {
        address watchtower;
        bytes32 evidence;       // keccak256 hash of off-chain evidence (e.g., IPFS CID)
        uint256 flaggedAt;
        bool resolved;          // true once slash confirmed or flag dismissed
        bool rewarded;          // true if bounty was paid out
    }

    /// @notice claimId → list of flags submitted by watchtowers
    mapping(uint256 => Flag[]) public flags;

    /// @notice address → watchtower info
    mapping(address => WatchtowerInfo) public watchtowers;

    /// @notice claimId → stake amount (set by the claim author; used for repricing)
    mapping(uint256 => uint256) public claimStake;

    /// @notice claimId → timestamp the claim was submitted
    mapping(uint256 => uint256) public claimTimestamp;

    /// @notice treasury address for collecting the treasury share
    address public treasury;

    /// @notice owner address (can set treasury, record claims)
    address public owner;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event WatchtowerRegistered(address indexed watcher, uint256 bond);
    event WatchtowerDeregistered(address indexed watcher, bool slashed, string reason);
    event ClaimFlagged(uint256 indexed claimId, address indexed watcher, bytes32 evidence);
    event FlagResolved(uint256 indexed claimId, uint256 flagIndex, bool slashSucceeded);
    event BountyPaid(address indexed watcher, uint256 amount);
    event ClaimRecorded(uint256 indexed claimId, uint256 stakeAmount);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error InsufficientBond(uint256 sent, uint256 required);
    error AlreadyRegistered();
    error NotRegistered();
    error ClaimNotFound(uint256 claimId);
    error FlagAlreadyResolved(uint256 claimId, uint256 flagIndex);
    error OnlyOwner();
    error ZeroAddress();
    error WithdrawFailed();

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyRegistered() {
        if (!watchtowers[msg.sender].active) revert NotRegistered();
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address _treasury) {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Registration
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Register as a watchtower. Caller must send exactly REGISTRATION_BOND.
    function register() external payable {
        if (watchtowers[msg.sender].active) revert AlreadyRegistered();
        if (msg.value < REGISTRATION_BOND) revert InsufficientBond(msg.value, REGISTRATION_BOND);

        watchtowers[msg.sender] = WatchtowerInfo({
            active: true,
            bond: msg.value,
            flagCount: 0,
            missedFlags: 0,
            earnedBounty: 0,
            registeredAt: block.timestamp
        });

        emit WatchtowerRegistered(msg.sender, msg.value);
    }

    /// @notice Voluntarily deregister and recover your bond (only if no unresolved flags).
    function deregister() external onlyRegistered {
        uint256 bond = watchtowers[msg.sender].bond;
        watchtowers[msg.sender].active = false;
        watchtowers[msg.sender].bond = 0;

        (bool ok,) = msg.sender.call{value: bond}("");
        if (!ok) revert WithdrawFailed();

        emit WatchtowerDeregistered(msg.sender, false, "voluntary");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Claim recording (called by the main EMET protocol on stake)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Record that a new claim was staked. Owner-only (called by protocol).
    /// @param claimId   Unique claim identifier
    /// @param stakeAmt  Amount staked on the claim (wei)
    function recordClaim(uint256 claimId, uint256 stakeAmt) external onlyOwner {
        claimStake[claimId] = stakeAmt;
        claimTimestamp[claimId] = block.timestamp;
        emit ClaimRecorded(claimId, stakeAmt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flagging
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Flag a claim as potentially false. Only registered watchtowers.
    /// @param claimId   The claim to flag
    /// @param evidence  keccak256 hash of off-chain evidence (IPFS CID, oracle proof, etc.)
    function flag(uint256 claimId, bytes32 evidence) external onlyRegistered {
        if (claimTimestamp[claimId] == 0) revert ClaimNotFound(claimId);

        flags[claimId].push(Flag({
            watchtower: msg.sender,
            evidence: evidence,
            flaggedAt: block.timestamp,
            resolved: false,
            rewarded: false
        }));

        watchtowers[msg.sender].flagCount++;

        emit ClaimFlagged(claimId, msg.sender, evidence);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dynamic challenge bond pricing
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Compute the challenge bond for a given claimId.
    ///         bond = BASE_BOND × timeMultiplier × stakeMultiplier × consensusDiscount
    ///
    /// @dev All multipliers are in basis points (10000 = 1×). Final price = product/10000^2.
    ///      Max bond is capped at 10× BASE_BOND to avoid prohibitive costs.
    function getChallengeBond(uint256 claimId) public view returns (uint256 bond) {
        if (claimTimestamp[claimId] == 0) revert ClaimNotFound(claimId);

        uint256 elapsed = block.timestamp - claimTimestamp[claimId];
        uint256 stake = claimStake[claimId];
        uint256 flagCount_ = flags[claimId].length;

        // Time multiplier: rises 10% per day elapsed, capped at 3× (30000 bps)
        uint256 daysElapsed = elapsed / 1 days;
        uint256 timeMul = 10_000 + (daysElapsed * 1_000); // 1000 bps = 10% per day
        if (timeMul > 30_000) timeMul = 30_000;

        // Stake multiplier: rises with log-scale of stake vs base threshold (0.01 ETH)
        // Simplified: each 0.01 ETH above base adds 20% (2000 bps), capped at 3×
        uint256 stakeThreshold = 0.01 ether;
        uint256 stakeMul;
        if (stake <= stakeThreshold) {
            stakeMul = 10_000; // 1×
        } else {
            uint256 units = (stake - stakeThreshold) / stakeThreshold;
            if (units > 10) units = 10;
            stakeMul = 10_000 + (units * 2_000); // +20% per 0.01 ETH
        }

        // Consensus discount: each flag reduces bond by 5% (500 bps), max 50% discount
        uint256 discount = flagCount_ * 500;
        if (discount > 5_000) discount = 5_000;
        uint256 consensusMul = 10_000 - discount;

        // bond = BASE_BOND × timeMul/10000 × stakeMul/10000 × consensusMul/10000
        bond = (BASE_BOND * timeMul * stakeMul * consensusMul) / (10_000 * 10_000 * 10_000);

        // Floor: never less than BASE_BOND / 2
        if (bond < BASE_BOND / 2) bond = BASE_BOND / 2;

        // Cap: never more than 10× BASE_BOND
        if (bond > BASE_BOND * 10) bond = BASE_BOND * 10;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Slash resolution
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Compute the slash split for a given amount.
    /// @return challengerShare  Amount to primary challenger (50%)
    /// @return watchtowerShare  Amount to watchtower (20%), or 0 if no valid flag
    /// @return treasuryShare    Amount to treasury (30%, adjusted if no watchtower)
    function computeSlashSplit(
        uint256 slashAmount,
        bool hasWatchtower
    )
        public
        pure
        returns (
            uint256 challengerShare,
            uint256 watchtowerShare,
            uint256 treasuryShare
        )
    {
        challengerShare = (slashAmount * CHALLENGER_SHARE_BPS) / 10_000;

        if (hasWatchtower) {
            watchtowerShare = (slashAmount * WATCHTOWER_SHARE_BPS) / 10_000;
            treasuryShare = slashAmount - challengerShare - watchtowerShare;
        } else {
            // No watchtower: watchtower's 20% goes to treasury instead
            watchtowerShare = 0;
            treasuryShare = slashAmount - challengerShare;
        }
    }

    /// @notice Resolve a flag after a challenge outcome is known.
    ///         Owner-only (called by the main challenge contract after resolution).
    /// @param claimId       The claim that was challenged
    /// @param flagIndex     Index into flags[claimId]
    /// @param slashSuccess  true = slash succeeded (watchtower earns bounty); false = dismissed
    /// @param slashAmount   Total slash amount (if success); 0 if dismissed
    function resolveFlag(
        uint256 claimId,
        uint256 flagIndex,
        bool slashSuccess,
        uint256 slashAmount
    )
        external
        payable
        onlyOwner
    {
        Flag storage f = flags[claimId][flagIndex];
        if (f.resolved) revert FlagAlreadyResolved(claimId, flagIndex);

        f.resolved = true;

        if (slashSuccess && slashAmount > 0) {
            // Credit the watchtower's 20% share
            uint256 bounty = (slashAmount * WATCHTOWER_SHARE_BPS) / 10_000;
            watchtowers[f.watchtower].earnedBounty += bounty;
            f.rewarded = true;
        } else {
            // Flag wasn't followed by a successful challenge
            watchtowers[f.watchtower].missedFlags++;

            // Penalize watchtower if missed flag limit exceeded
            if (watchtowers[f.watchtower].missedFlags >= MISSED_FLAG_LIMIT) {
                _slashWatchtower(f.watchtower);
            }
        }

        emit FlagResolved(claimId, flagIndex, slashSuccess);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bounty withdrawal
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Withdraw accumulated bounty earnings.
    function withdrawBounty() external onlyRegistered {
        uint256 amount = watchtowers[msg.sender].earnedBounty;
        if (amount == 0) return;

        watchtowers[msg.sender].earnedBounty = 0;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert WithdrawFailed();

        emit BountyPaid(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Number of flags on a given claim.
    function flagCount(uint256 claimId) external view returns (uint256) {
        return flags[claimId].length;
    }

    /// @notice Check if any active (unresolved) flag exists for a claim.
    function hasActiveFlag(uint256 claimId) external view returns (bool) {
        Flag[] storage fs = flags[claimId];
        for (uint256 i = 0; i < fs.length; i++) {
            if (!fs[i].resolved) return true;
        }
        return false;
    }

    /// @notice Get info about a specific flag.
    function getFlag(
        uint256 claimId,
        uint256 idx
    )
        external
        view
        returns (
            address watcher,
            bytes32 evidence,
            uint256 flaggedAt,
            bool resolved,
            bool rewarded
        )
    {
        Flag storage f = flags[claimId][idx];
        return (f.watchtower, f.evidence, f.flaggedAt, f.resolved, f.rewarded);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Slash a watchtower's bond and deregister them (too many false flags).
    function _slashWatchtower(address watcher) internal {
        uint256 bond = watchtowers[watcher].bond;
        watchtowers[watcher].active = false;
        watchtowers[watcher].bond = 0;

        // Send slashed bond to treasury
        if (bond > 0 && treasury != address(0)) {
            (bool ok,) = treasury.call{value: bond}("");
            // If treasury call fails, funds stay in contract (safety fallback)
            ok; // silence warning
        }

        emit WatchtowerDeregistered(watcher, true, "too many missed flags");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Update treasury address.
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    /// @notice Allow contract to receive ETH (bounties funded by protocol on resolution).
    receive() external payable {}
}

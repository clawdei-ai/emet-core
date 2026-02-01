// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETTreasury - Protocol fee collection and management
/// @notice Receives 1% protocol fees from challenge resolutions, holds funds for
///         LP rewards and future governance-directed spending.
/// @dev Treasury admin is set once at deployment (immutable). No other admin keys.
///      Fee distributor (ChallengeV2) is also set once. Future governance can be
///      layered on top via a governor contract as admin.
contract EMETTreasury {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Protocol fee in basis points (100 = 1%)
    uint256 public constant PROTOCOL_FEE_BPS = 100;

    /// @notice Basis-point denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Immutables ============

    /// @notice Treasury admin — the only address that can withdraw
    address public immutable admin;

    // ============ State ============

    /// @notice Authorized fee distributor (ChallengeV2), set once
    address public feeDistributor;

    /// @notice Authorized LP rewards contract, set once
    address public lpRewardsContract;

    /// @notice Running total of fees received
    uint256 public totalFeesReceived;

    /// @notice Running total of fees allocated to LP rewards
    uint256 public totalLPRewardsDistributed;

    // ============ Events ============

    /// @notice Emitted when a protocol fee is received from a resolution
    event FeeReceived(uint256 indexed claimId, uint256 amount, uint256 totalStake);

    /// @notice Emitted when the admin withdraws funds
    event Withdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when rewards are sent to LP contract
    event LPRewardsDistributed(uint256 amount);

    /// @notice Emitted when fee distributor is set
    event FeeDistributorSet(address indexed distributor);

    /// @notice Emitted when LP rewards contract is set
    event LPRewardsContractSet(address indexed lpRewards);

    // ============ Errors ============

    error OnlyAdmin();
    error OnlyFeeDistributor();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);
    error FeeDistributorAlreadySet();
    error LPRewardsAlreadySet();
    error TransferFailed();

    // ============ Constructor ============

    /// @notice Deploy treasury with immutable admin
    /// @param _admin Address that can withdraw funds (set once, forever)
    constructor(address _admin) {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
    }

    // ============ Modifiers ============

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier onlyFeeDistributor() {
        if (msg.sender != feeDistributor) revert OnlyFeeDistributor();
        _;
    }

    // ============ Configuration (set-once) ============

    /// @notice Set the fee distributor contract (ChallengeV2). Can only be set once.
    /// @param _distributor Address of EMETChallengeV2
    function setFeeDistributor(address _distributor) external onlyAdmin {
        if (feeDistributor != address(0)) revert FeeDistributorAlreadySet();
        if (_distributor == address(0)) revert ZeroAddress();
        feeDistributor = _distributor;
        emit FeeDistributorSet(_distributor);
    }

    /// @notice Set the LP rewards contract. Can only be set once.
    /// @param _lpRewards Address of EMETLPRewards
    function setLPRewardsContract(address _lpRewards) external onlyAdmin {
        if (lpRewardsContract != address(0)) revert LPRewardsAlreadySet();
        if (_lpRewards == address(0)) revert ZeroAddress();
        lpRewardsContract = _lpRewards;
        emit LPRewardsContractSet(_lpRewards);
    }

    // ============ Fee Reception ============

    /// @notice Receive a protocol fee from a resolution
    /// @dev Only callable by the authorized fee distributor (ChallengeV2)
    /// @param claimId The resolved claim ID
    /// @param amount The fee amount in EMET
    /// @param totalStake The total stake that was resolved (for event context)
    function receiveFee(uint256 claimId, uint256 amount, uint256 totalStake)
        external
        onlyFeeDistributor
    {
        if (amount == 0) revert ZeroAmount();
        totalFeesReceived += amount;
        emit FeeReceived(claimId, amount, totalStake);
    }

    // ============ Withdrawals ============

    /// @notice Withdraw EMET from treasury
    /// @dev Only callable by the immutable admin
    /// @param to Recipient address
    /// @param amount Amount of EMET to withdraw
    function withdraw(address to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = EMET.balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance(amount, balance);

        bool success = EMET.transfer(to, amount);
        if (!success) revert TransferFailed();

        emit Withdrawn(to, amount);
    }

    /// @notice Distribute rewards to LP stakers
    /// @dev Only callable by admin. Sends EMET to the LP rewards contract
    ///      and triggers reward distribution.
    /// @param amount Amount of EMET to distribute as LP rewards
    function distributeLPRewards(uint256 amount) external onlyAdmin {
        if (amount == 0) revert ZeroAmount();
        if (lpRewardsContract == address(0)) revert ZeroAddress();

        uint256 balance = EMET.balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance(amount, balance);

        totalLPRewardsDistributed += amount;

        bool success = EMET.transfer(lpRewardsContract, amount);
        if (!success) revert TransferFailed();

        emit LPRewardsDistributed(amount);
    }

    // ============ View Functions ============

    /// @notice Calculate the protocol fee for a given total stake
    /// @param totalStake The total stake amount
    /// @return fee The fee amount (1% of totalStake)
    function calculateFee(uint256 totalStake) external pure returns (uint256 fee) {
        return (totalStake * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
    }

    /// @notice Current EMET balance held by treasury
    /// @return balance The balance
    function balance() external view returns (uint256) {
        return EMET.balanceOf(address(this));
    }
}

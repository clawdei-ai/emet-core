// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IJuryPool} from "./interfaces/IJuryPool.sol";
import {EMETReputation} from "./EMETReputation.sol";

/// @title EMETJuryPool - Juror registration and weighted random selection
/// @notice Manages the pool of eligible jurors for EMET dispute resolution.
///         Jurors must have reputation >= MIN_JUROR_REP to register.
///         Selection is weighted by reputation (higher rep = higher chance).
/// @dev Uses block.prevrandao + challengeId for entropy. No admin functions.
contract EMETJuryPool is IJuryPool {
    // ============ Constants ============

    /// @notice Minimum reputation required to register as a juror
    int256 public constant MIN_JUROR_REP = 50;

    // ============ Immutables ============

    /// @notice Reputation contract for eligibility checks
    EMETReputation public immutable reputationContract;

    // ============ State ============

    /// @notice Whether an address is registered as a juror
    mapping(address => bool) public registeredJurors;

    /// @notice Index of juror in the pool (for O(1) removal)
    mapping(address => uint256) internal jurorIndex;

    /// @notice Array of registered jurors
    address[] public jurorPool;

    /// @notice Authorized challenge contract that can select juries
    address public challengeContract;

    /// @notice Deployer, used only to set challenge contract once
    address public immutable deployer;

    // ============ Errors ============

    error InsufficientReputation(address juror, int256 current, int256 required);
    error AlreadyRegistered(address juror);
    error NotRegistered(address juror);
    error InsufficientJurors(uint256 available, uint256 required);
    error OnlyChallengeContract();
    error OnlyDeployer();
    error ChallengeContractAlreadySet();
    error ZeroAddress();
    error InvalidJurySize();

    // ============ Constructor ============

    /// @notice Deploy the jury pool linked to reputation contract
    /// @param _reputation Address of EMETReputation contract
    constructor(address _reputation) {
        if (_reputation == address(0)) revert ZeroAddress();
        reputationContract = EMETReputation(_reputation);
        deployer = msg.sender;
    }

    // ============ Configuration ============

    /// @notice Set the challenge contract that can select juries. Set once only.
    /// @param _challengeContract Address of EMETChallengeV3
    function setChallengeContract(address _challengeContract) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (challengeContract != address(0)) revert ChallengeContractAlreadySet();
        if (_challengeContract == address(0)) revert ZeroAddress();
        challengeContract = _challengeContract;
    }

    // ============ Registration ============

    /// @notice Register as a juror (must have reputation >= MIN_JUROR_REP)
    /// @dev Anyone can call if they meet the reputation requirement
    function registerJuror() external {
        if (registeredJurors[msg.sender]) revert AlreadyRegistered(msg.sender);

        int256 rep = reputationContract.getReputation(msg.sender);
        if (rep < MIN_JUROR_REP) {
            revert InsufficientReputation(msg.sender, rep, MIN_JUROR_REP);
        }

        registeredJurors[msg.sender] = true;
        jurorIndex[msg.sender] = jurorPool.length;
        jurorPool.push(msg.sender);

        emit JurorRegistered(msg.sender, rep);
    }

    /// @notice Unregister as a juror
    /// @dev Removes juror from pool. Can be called anytime by the juror.
    function unregisterJuror() external {
        if (!registeredJurors[msg.sender]) revert NotRegistered(msg.sender);

        _removeJuror(msg.sender);

        emit JurorUnregistered(msg.sender);
    }

    // ============ Jury Selection ============

    /// @notice Select a jury for a challenge using weighted random selection
    /// @dev Only callable by the authorized challenge contract.
    ///      Uses prevrandao + challengeId as entropy source.
    ///      Selection is weighted by reputation (higher rep = higher probability).
    /// @param challengeId The challenge ID for entropy
    /// @param jurySize Number of jurors to select (3, 7, or 11)
    /// @param excludes Addresses to exclude from selection (challenger, submitter)
    /// @return jurors Array of selected juror addresses
    function selectJury(
        uint256 challengeId,
        uint256 jurySize,
        address[] calldata excludes
    ) external returns (address[] memory jurors) {
        if (msg.sender != challengeContract) revert OnlyChallengeContract();
        if (jurySize == 0 || jurySize > 11) revert InvalidJurySize();

        // Build eligible pool (registered + still meets rep requirement + not excluded)
        address[] memory eligible = _buildEligiblePool(excludes);

        if (eligible.length < jurySize) {
            revert InsufficientJurors(eligible.length, jurySize);
        }

        // Weighted random selection without replacement
        jurors = _weightedRandomSelect(eligible, jurySize, challengeId);

        emit JurySelected(challengeId, jurors);
        return jurors;
    }

    // ============ Internal Functions ============

    /// @notice Build array of eligible jurors (registered, meets rep, not excluded)
    function _buildEligiblePool(address[] calldata excludes)
        internal
        view
        returns (address[] memory eligible)
    {
        // First pass: count eligible
        uint256 count = 0;
        for (uint256 i = 0; i < jurorPool.length; i++) {
            if (_isEligibleAndNotExcluded(jurorPool[i], excludes)) {
                count++;
            }
        }

        // Second pass: build array
        eligible = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < jurorPool.length; i++) {
            if (_isEligibleAndNotExcluded(jurorPool[i], excludes)) {
                eligible[idx++] = jurorPool[i];
            }
        }
    }

    /// @notice Check if juror is eligible and not in excludes list
    function _isEligibleAndNotExcluded(address juror, address[] calldata excludes)
        internal
        view
        returns (bool)
    {
        // Must still meet reputation requirement (can change over time)
        if (reputationContract.getReputation(juror) < MIN_JUROR_REP) {
            return false;
        }

        // Must not be excluded
        for (uint256 i = 0; i < excludes.length; i++) {
            if (juror == excludes[i]) {
                return false;
            }
        }

        return true;
    }

    /// @notice Weighted random selection without replacement
    /// @dev Uses reputation as weight. Higher rep = higher selection probability.
    function _weightedRandomSelect(
        address[] memory pool,
        uint256 selectCount,
        uint256 challengeId
    ) internal view returns (address[] memory selected) {
        selected = new address[](selectCount);
        uint256 poolSize = pool.length;

        // Calculate initial weights (reputation scores)
        uint256[] memory weights = new uint256[](poolSize);
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < poolSize; i++) {
            int256 rep = reputationContract.getReputation(pool[i]);
            // Convert to uint256, floor at 1 (minimum weight)
            uint256 weight = rep > 0 ? uint256(rep) : 1;
            weights[i] = weight;
            totalWeight += weight;
        }

        // Select jurors one by one
        uint256 entropy = uint256(keccak256(abi.encodePacked(block.prevrandao, challengeId)));

        for (uint256 s = 0; s < selectCount; s++) {
            // Generate random point in [0, totalWeight)
            uint256 randomPoint = entropy % totalWeight;

            // Find the juror at this point
            uint256 cumulative = 0;
            for (uint256 i = 0; i < poolSize; i++) {
                if (weights[i] == 0) continue; // Already selected

                cumulative += weights[i];
                if (randomPoint < cumulative) {
                    selected[s] = pool[i];

                    // Remove from future selection
                    totalWeight -= weights[i];
                    weights[i] = 0;

                    // Rotate entropy for next selection
                    entropy = uint256(keccak256(abi.encodePacked(entropy, pool[i])));
                    break;
                }
            }
        }
    }

    /// @notice Remove a juror from the pool (swap-and-pop)
    function _removeJuror(address juror) internal {
        uint256 idx = jurorIndex[juror];
        uint256 lastIdx = jurorPool.length - 1;

        if (idx != lastIdx) {
            // Swap with last element
            address lastJuror = jurorPool[lastIdx];
            jurorPool[idx] = lastJuror;
            jurorIndex[lastJuror] = idx;
        }

        jurorPool.pop();
        delete jurorIndex[juror];
        delete registeredJurors[juror];
    }

    // ============ View Functions ============

    /// @notice Check if an address is eligible to be a juror
    /// @param juror Address to check
    /// @return eligible True if reputation >= MIN_JUROR_REP
    function isEligible(address juror) external view returns (bool eligible) {
        return reputationContract.getReputation(juror) >= MIN_JUROR_REP;
    }

    /// @notice Check if an address is registered as a juror
    /// @param juror Address to check
    /// @return registered True if registered
    function isRegistered(address juror) external view returns (bool registered) {
        return registeredJurors[juror];
    }

    /// @notice Get the number of registered jurors
    /// @return count Number of registered jurors
    function getJurorCount() external view returns (uint256 count) {
        return jurorPool.length;
    }

    /// @notice Get registered juror at index
    /// @param index Index in the juror pool
    /// @return juror Address of the juror
    function getJurorAt(uint256 index) external view returns (address juror) {
        return jurorPool[index];
    }

    /// @notice Get all registered jurors
    /// @return jurors Array of all registered juror addresses
    function getAllJurors() external view returns (address[] memory jurors) {
        return jurorPool;
    }
}

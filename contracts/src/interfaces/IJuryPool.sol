// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title IJuryPool - Interface for EMET jury selection system
/// @notice Defines the interface for juror registration and selection
interface IJuryPool {
    /// @notice Emitted when a juror registers
    event JurorRegistered(address indexed juror, int256 reputation);

    /// @notice Emitted when a juror unregisters
    event JurorUnregistered(address indexed juror);

    /// @notice Emitted when a jury is selected for a challenge
    event JurySelected(uint256 indexed challengeId, address[] jurors);

    /// @notice Register as a juror (must meet reputation requirement)
    function registerJuror() external;

    /// @notice Unregister as a juror
    function unregisterJuror() external;

    /// @notice Check if an address is eligible to be a juror
    /// @param juror Address to check
    /// @return eligible True if eligible
    function isEligible(address juror) external view returns (bool eligible);

    /// @notice Check if an address is registered as a juror
    /// @param juror Address to check
    /// @return registered True if registered
    function isRegistered(address juror) external view returns (bool registered);

    /// @notice Select a jury for a challenge
    /// @dev Uses weighted random selection based on reputation
    /// @param challengeId The challenge ID for entropy
    /// @param jurySize Number of jurors to select
    /// @param excludes Addresses to exclude (challenger, claim submitter)
    /// @return jurors Array of selected juror addresses
    function selectJury(
        uint256 challengeId,
        uint256 jurySize,
        address[] calldata excludes
    ) external returns (address[] memory jurors);

    /// @notice Get the number of registered jurors
    /// @return count Number of registered jurors
    function getJurorCount() external view returns (uint256 count);

    /// @notice Get registered juror at index
    /// @param index Index in the juror pool
    /// @return juror Address of the juror
    function getJurorAt(uint256 index) external view returns (address juror);
}

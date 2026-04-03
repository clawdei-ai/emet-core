// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {EMETTrustGate} from "./EMETTrustGate.sol";

/// @title EMETGatedRouter — Abstract base contract for trust-gated agent routing
/// @notice Inherit this contract to add EMET trust enforcement to any agent routing,
///         crew formation, or task assignment system in a single modifier.
///
/// @dev Usage:
///   ```solidity
///   contract MyAgentRouter is EMETGatedRouter {
///       constructor(address trustGate)
///           EMETGatedRouter(trustGate, EMETTrustGate.Policy.STANDARD) {}
///
///       function assignTask(address agent, bytes calldata task)
///           external
///           onlyTrusted(agent)
///       {
///           // agent has passed EMET trust check
///           (bool ok,) = agent.call(task);
///           require(ok, "task failed");
///       }
///
///       // Expose management with your own access control:
///       function updatePolicy(EMETTrustGate.Policy p) external onlyOwner {
///           _setDefaultPolicy(p);
///       }
///       function grantBypass(address a, string calldata r) external onlyOwner {
///           _addBypass(a, r);
///       }
///       function revokeBypass(address a) external onlyOwner {
///           _removeBypass(a);
///       }
///   }
///   ```
///
/// Modifiers:
///   onlyTrusted(agent)             — checks agent against default policy
///   allTrusted(agents)             — checks all agents in an array
///   onlyTrustedWith(agent, policy) — checks agent against a specific policy
///
/// Internal management (inheritors call these from their own access-controlled functions):
///   _setDefaultPolicy(policy)
///   _addBypass(agent, reason)
///   _removeBypass(agent)
///
/// Bootstrap path (cold start — agents with no EMET history):
///   Call _addBypass() to whitelist trusted agents before they have track records.
///   All bypass grants are logged on-chain for auditability.
///
/// @custom:version 0.15.0
/// @custom:design-source docs/emet-architecture-v2-design.md
abstract contract EMETGatedRouter {

    // ============ State ============

    /// @notice The deployed EMETTrustGate instance
    EMETTrustGate public immutable trustGate;

    /// @notice Default trust policy applied by onlyTrusted modifier
    EMETTrustGate.Policy public defaultPolicy;

    /// @notice Bootstrap bypass list: agents exempt from gate checks
    /// @dev Use for cold-start (no EMET history yet) or known trusted partners.
    ///      All grants emitted on-chain — cannot be hidden.
    mapping(address => bool) private _bypassed;

    /// @notice Number of agents currently on the bypass list
    uint256 public bypassCount;

    // ============ Events ============

    /// @notice Emitted when default policy is updated
    event DefaultPolicyUpdated(EMETTrustGate.Policy oldPolicy, EMETTrustGate.Policy newPolicy);

    /// @notice Emitted when an agent is added to the bypass list
    event BypassGranted(address indexed agent, string reason, address grantedBy);

    /// @notice Emitted when an agent is removed from the bypass list
    event BypassRevoked(address indexed agent, address revokedBy);

    /// @notice Emitted when a bypassed agent passes through a gate check
    event BypassUsed(address indexed agent, address indexed caller);

    // ============ Errors ============

    error ZeroTrustGateAddress();
    error TrustCheckFailed(address agent, string reason);
    error AgentNotBypassed(address agent);
    error AgentAlreadyBypassed(address agent);
    error EmptyAgentArray();

    // ============ Constructor ============

    /// @param _trustGate     Address of deployed EMETTrustGate contract
    /// @param _defaultPolicy Trust policy to use for onlyTrusted modifier
    constructor(address _trustGate, EMETTrustGate.Policy _defaultPolicy) {
        if (_trustGate == address(0)) revert ZeroTrustGateAddress();
        trustGate     = EMETTrustGate(_trustGate);
        defaultPolicy = _defaultPolicy;
    }

    // ============ Modifiers ============

    /// @notice Gate: revert if agent fails default trust policy
    modifier onlyTrusted(address agent) {
        _checkTrust(agent, defaultPolicy);
        _;
    }

    /// @notice Gate: revert if ANY agent in the array fails default trust policy
    modifier allTrusted(address[] calldata agents) {
        if (agents.length == 0) revert EmptyAgentArray();
        for (uint256 i = 0; i < agents.length; i++) {
            _checkTrust(agents[i], defaultPolicy);
        }
        _;
    }

    /// @notice Gate: revert if agent fails a specific trust policy (ignores defaultPolicy)
    modifier onlyTrustedWith(address agent, EMETTrustGate.Policy policy) {
        _checkTrust(agent, policy);
        _;
    }

    // ============ View Helpers ============

    /// @notice Query trust without modifying state
    function queryTrust(address agent, EMETTrustGate.Policy policy)
        external
        view
        returns (bool passes, string memory reason)
    {
        return trustGate.query(agent, policy);
    }

    /// @notice Full trust result struct
    function evaluateTrust(address agent, EMETTrustGate.Policy policy)
        external
        view
        returns (EMETTrustGate.TrustResult memory)
    {
        return trustGate.evaluate(agent, policy);
    }

    /// @notice Check if an agent is currently on the bypass list
    function isBypassed(address agent) external view returns (bool) {
        return _bypassed[agent];
    }

    // ============ Internal Management ============
    // Inheritors expose these via their own access-controlled public functions.

    /// @dev Update the default trust policy. Call from an access-controlled public function.
    function _setDefaultPolicy(EMETTrustGate.Policy policy) internal {
        EMETTrustGate.Policy old = defaultPolicy;
        defaultPolicy = policy;
        emit DefaultPolicyUpdated(old, policy);
    }

    /// @dev Add agent to bypass list. Call from an access-controlled public function.
    function _addBypass(address agent, string calldata reason) internal {
        if (_bypassed[agent]) revert AgentAlreadyBypassed(agent);
        _bypassed[agent] = true;
        bypassCount++;
        emit BypassGranted(agent, reason, msg.sender);
    }

    /// @dev Remove agent from bypass list. Call from an access-controlled public function.
    function _removeBypass(address agent) internal {
        if (!_bypassed[agent]) revert AgentNotBypassed(agent);
        _bypassed[agent] = false;
        bypassCount--;
        emit BypassRevoked(agent, msg.sender);
    }

    // ============ Internal Trust Check ============

    /// @dev Core trust check. Called by all modifiers.
    ///      Bypass list checked first (O(1), no external call).
    function _checkTrust(address agent, EMETTrustGate.Policy policy) internal {
        if (_bypassed[agent]) {
            emit BypassUsed(agent, msg.sender);
            return;
        }
        (bool passes, string memory reason) = trustGate.check(agent, policy);
        if (!passes) revert TrustCheckFailed(agent, reason);
    }
}

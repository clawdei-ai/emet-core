// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETCrossModel - Cross-architecture AI verification for EMET Protocol
/// @notice Multiple AI models (Claude, Grok, GPT, Llama, etc.) can independently
///         verify claims. Agreement across different architectures = stronger truth signal.
/// @dev Models must stake EMET to register (skin in the game).
///      Consensus = 3+ models agree with avg confidence > 70%.
///      Different architectures agreeing is more meaningful than same architecture.
contract EMETCrossModel {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Minimum stake required to register a model
    uint256 public constant MIN_MODEL_STAKE = 100 ether;

    /// @notice Minimum models for consensus
    uint256 public constant MIN_CONSENSUS_MODELS = 3;

    /// @notice Minimum average confidence for consensus (percentage)
    uint256 public constant MIN_CONSENSUS_CONFIDENCE = 70;

    /// @notice Initial reputation for new models
    uint256 public constant INITIAL_REPUTATION = 100;

    // ============ Types ============

    /// @notice Registered AI model information
    struct Model {
        string name;           // "Claude", "Grok", "GPT-4", etc.
        string architecture;   // "anthropic", "xai", "openai", "meta"
        address operator;      // Address that submits attestations for this model
        uint256 reputation;    // Model-level reputation (starts at 100)
        uint256 stake;         // EMET staked for this model
        uint256 totalAttestations;  // Total attestations submitted
        bool active;           // Whether model is active
    }

    /// @notice An attestation from a model about a claim
    struct Attestation {
        uint256 claimId;       // The claim being attested
        uint256 modelId;       // The model making the attestation
        bool supportsClaim;    // true = verifies claim, false = disputes it
        uint256 confidence;    // 0-100 confidence percentage
        string reasoning;      // On-chain reasoning for the attestation
        uint256 timestamp;     // When attestation was submitted
    }

    /// @notice Consensus view for a claim
    struct Consensus {
        uint256 supportingModels;     // Models that support the claim
        uint256 disputingModels;      // Models that dispute the claim
        uint256 avgConfidenceFor;     // Average confidence of supporting attestations
        uint256 avgConfidenceAgainst; // Average confidence of disputing attestations
        bool consensusReached;        // True if >= 3 models agree with avg confidence > 70%
        bool consensusSupports;       // What the consensus says (if reached)
    }

    // ============ State ============

    /// @notice All registered models indexed by ID
    mapping(uint256 => Model) public models;

    /// @notice Total number of models
    uint256 public modelCount;

    /// @notice Mapping from operator address to their model ID
    mapping(address => uint256) public operatorToModel;

    /// @notice Attestations per claim: claimId => modelId => Attestation
    mapping(uint256 => mapping(uint256 => Attestation)) private attestations;

    /// @notice Track which models have attested to a claim
    mapping(uint256 => uint256[]) private claimAttestors;

    /// @notice Track attestation existence: claimId => modelId => exists
    mapping(uint256 => mapping(uint256 => bool)) private hasAttested;

    /// @notice Governance address for reputation updates
    address public governance;

    /// @notice Deployer address for initial setup
    address public immutable deployer;

    // ============ Events ============

    /// @notice Emitted when a new model is registered
    event ModelRegistered(
        uint256 indexed modelId,
        string name,
        string architecture,
        address indexed operator,
        uint256 stake
    );

    /// @notice Emitted when a model is deactivated
    event ModelDeactivated(uint256 indexed modelId, address indexed operator);

    /// @notice Emitted when an attestation is submitted
    event AttestationSubmitted(
        uint256 indexed claimId,
        uint256 indexed modelId,
        bool supportsClaim,
        uint256 confidence,
        string reasoning
    );

    /// @notice Emitted when model reputation is updated
    event ReputationUpdated(
        uint256 indexed modelId,
        uint256 oldReputation,
        uint256 newReputation,
        int256 delta
    );

    /// @notice Emitted when governance is set
    event GovernanceSet(address indexed governance);

    // ============ Errors ============

    error InsufficientStake(uint256 provided, uint256 required);
    error OperatorAlreadyRegistered(address operator);
    error ModelDoesNotExist(uint256 modelId);
    error ModelNotActive(uint256 modelId);
    error NotModelOperator(address caller, uint256 modelId);
    error AlreadyAttested(uint256 claimId, uint256 modelId);
    error InvalidConfidence(uint256 confidence);
    error TransferFailed();
    error ZeroAddress();
    error OnlyGovernance();
    error OnlyDeployer();
    error GovernanceAlreadySet();
    error EmptyName();
    error EmptyArchitecture();

    // ============ Constructor ============

    constructor() {
        deployer = msg.sender;
    }

    // ============ Configuration ============

    /// @notice Set the governance address. Can only be set once.
    /// @param _governance Address that can update model reputations
    function setGovernance(address _governance) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (governance != address(0)) revert GovernanceAlreadySet();
        if (_governance == address(0)) revert ZeroAddress();
        governance = _governance;
        emit GovernanceSet(_governance);
    }

    // ============ Model Registration ============

    /// @notice Register a new AI model
    /// @dev Operator must approve EMET transfer before calling
    /// @param name Model name (e.g., "Claude", "Grok", "GPT-4")
    /// @param architecture Model architecture family (e.g., "anthropic", "xai", "openai")
    /// @param stakeAmount Amount of EMET to stake (must be >= MIN_MODEL_STAKE)
    /// @return modelId The ID of the newly registered model
    function registerModel(
        string calldata name,
        string calldata architecture,
        uint256 stakeAmount
    ) external returns (uint256 modelId) {
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(architecture).length == 0) revert EmptyArchitecture();
        if (stakeAmount < MIN_MODEL_STAKE) revert InsufficientStake(stakeAmount, MIN_MODEL_STAKE);
        if (operatorToModel[msg.sender] != 0) revert OperatorAlreadyRegistered(msg.sender);

        // Transfer stake
        if (!EMET.transferFrom(msg.sender, address(this), stakeAmount)) revert TransferFailed();

        // Create model (ID starts at 1 to distinguish from unset)
        modelId = ++modelCount;

        models[modelId] = Model({
            name: name,
            architecture: architecture,
            operator: msg.sender,
            reputation: INITIAL_REPUTATION,
            stake: stakeAmount,
            totalAttestations: 0,
            active: true
        });

        operatorToModel[msg.sender] = modelId;

        emit ModelRegistered(modelId, name, architecture, msg.sender, stakeAmount);

        return modelId;
    }

    /// @notice Deactivate a model and withdraw stake
    /// @dev Only callable by the model's operator
    function deactivateModel() external {
        uint256 modelId = operatorToModel[msg.sender];
        if (modelId == 0) revert ModelDoesNotExist(modelId);

        Model storage model = models[modelId];
        if (!model.active) revert ModelNotActive(modelId);

        model.active = false;

        // Return stake
        uint256 stake = model.stake;
        model.stake = 0;
        if (!EMET.transfer(msg.sender, stake)) revert TransferFailed();

        emit ModelDeactivated(modelId, msg.sender);
    }

    // ============ Attestation ============

    /// @notice Submit an attestation for a claim
    /// @dev Each model can only attest once per claim
    /// @param claimId The claim to attest
    /// @param supportsClaim True if model verifies the claim, false if disputes
    /// @param confidence Confidence level 0-100
    /// @param reasoning On-chain reasoning for the attestation
    function attest(
        uint256 claimId,
        bool supportsClaim,
        uint256 confidence,
        string calldata reasoning
    ) external {
        uint256 modelId = operatorToModel[msg.sender];
        if (modelId == 0) revert ModelDoesNotExist(modelId);

        Model storage model = models[modelId];
        if (!model.active) revert ModelNotActive(modelId);
        if (confidence > 100) revert InvalidConfidence(confidence);
        if (hasAttested[claimId][modelId]) revert AlreadyAttested(claimId, modelId);

        // Record attestation
        attestations[claimId][modelId] = Attestation({
            claimId: claimId,
            modelId: modelId,
            supportsClaim: supportsClaim,
            confidence: confidence,
            reasoning: reasoning,
            timestamp: block.timestamp
        });

        hasAttested[claimId][modelId] = true;
        claimAttestors[claimId].push(modelId);
        model.totalAttestations++;

        emit AttestationSubmitted(claimId, modelId, supportsClaim, confidence, reasoning);
    }

    // ============ Reputation Management ============

    /// @notice Update a model's reputation (governance only)
    /// @dev Called after reviewing attestation accuracy
    /// @param modelId The model to update
    /// @param delta The reputation change (can be negative)
    function updateModelReputation(uint256 modelId, int256 delta) external {
        if (msg.sender != governance) revert OnlyGovernance();
        if (modelId == 0 || modelId > modelCount) revert ModelDoesNotExist(modelId);

        Model storage model = models[modelId];
        uint256 oldReputation = model.reputation;

        // Apply delta with floor at 0
        if (delta < 0 && uint256(-delta) > model.reputation) {
            model.reputation = 0;
        } else if (delta < 0) {
            model.reputation -= uint256(-delta);
        } else {
            model.reputation += uint256(delta);
        }

        emit ReputationUpdated(modelId, oldReputation, model.reputation, delta);
    }

    // ============ Consensus Queries ============

    /// @notice Get consensus view for a claim
    /// @param claimId The claim to query
    /// @return consensus The consensus struct with all computed values
    function getConsensus(uint256 claimId) external view returns (Consensus memory consensus) {
        uint256[] storage attestorIds = claimAttestors[claimId];

        uint256 supportSum = 0;
        uint256 disputeSum = 0;

        for (uint256 i = 0; i < attestorIds.length; i++) {
            uint256 modelId = attestorIds[i];
            Attestation storage a = attestations[claimId][modelId];

            if (a.supportsClaim) {
                consensus.supportingModels++;
                supportSum += a.confidence;
            } else {
                consensus.disputingModels++;
                disputeSum += a.confidence;
            }
        }

        // Calculate averages
        if (consensus.supportingModels > 0) {
            consensus.avgConfidenceFor = supportSum / consensus.supportingModels;
        }
        if (consensus.disputingModels > 0) {
            consensus.avgConfidenceAgainst = disputeSum / consensus.disputingModels;
        }

        // Determine if consensus is reached
        // Consensus = 3+ models agree with avg confidence > 70%
        if (consensus.supportingModels >= MIN_CONSENSUS_MODELS &&
            consensus.avgConfidenceFor >= MIN_CONSENSUS_CONFIDENCE) {
            consensus.consensusReached = true;
            consensus.consensusSupports = true;
        } else if (consensus.disputingModels >= MIN_CONSENSUS_MODELS &&
                   consensus.avgConfidenceAgainst >= MIN_CONSENSUS_CONFIDENCE) {
            consensus.consensusReached = true;
            consensus.consensusSupports = false;
        }

        return consensus;
    }

    /// @notice Get all attestations for a claim
    /// @param claimId The claim to query
    /// @return Array of attestations
    function getAttestations(uint256 claimId) external view returns (Attestation[] memory) {
        uint256[] storage attestorIds = claimAttestors[claimId];
        Attestation[] memory result = new Attestation[](attestorIds.length);

        for (uint256 i = 0; i < attestorIds.length; i++) {
            result[i] = attestations[claimId][attestorIds[i]];
        }

        return result;
    }

    /// @notice Get a single attestation
    /// @param claimId The claim ID
    /// @param modelId The model ID
    /// @return The attestation (empty if not found)
    function getAttestation(uint256 claimId, uint256 modelId) external view returns (Attestation memory) {
        return attestations[claimId][modelId];
    }

    /// @notice Check if a model has attested to a claim
    /// @param claimId The claim to check
    /// @param modelId The model to check
    /// @return True if model has already attested
    function hasModelAttested(uint256 claimId, uint256 modelId) external view returns (bool) {
        return hasAttested[claimId][modelId];
    }

    // ============ Model Queries ============

    /// @notice Get model information
    /// @param modelId The model ID to query
    /// @return The model struct
    function getModel(uint256 modelId) external view returns (Model memory) {
        if (modelId == 0 || modelId > modelCount) revert ModelDoesNotExist(modelId);
        return models[modelId];
    }

    /// @notice Get model ID for an operator address
    /// @param operator The operator address
    /// @return modelId The model ID (0 if not registered)
    function getModelByOperator(address operator) external view returns (uint256 modelId) {
        return operatorToModel[operator];
    }

    /// @notice Get all active models
    /// @return activeModels Array of active model IDs
    function getActiveModels() external view returns (uint256[] memory activeModels) {
        // First count active models
        uint256 count = 0;
        for (uint256 i = 1; i <= modelCount; i++) {
            if (models[i].active) count++;
        }

        // Populate array
        activeModels = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= modelCount; i++) {
            if (models[i].active) {
                activeModels[idx++] = i;
            }
        }

        return activeModels;
    }

    /// @notice Get number of attestations for a claim
    /// @param claimId The claim to query
    /// @return The number of attestations
    function getAttestationCount(uint256 claimId) external view returns (uint256) {
        return claimAttestors[claimId].length;
    }

    /// @notice Get unique architectures that have attested to a claim
    /// @dev Useful for determining cross-architecture agreement strength
    /// @param claimId The claim to query
    /// @return forArchitectures Number of unique architectures supporting
    /// @return againstArchitectures Number of unique architectures disputing
    function getArchitectureDiversity(uint256 claimId) external view returns (
        uint256 forArchitectures,
        uint256 againstArchitectures
    ) {
        uint256[] storage attestorIds = claimAttestors[claimId];

        // Track seen architectures (simple approach for limited set)
        bytes32[] memory seenFor = new bytes32[](attestorIds.length);
        bytes32[] memory seenAgainst = new bytes32[](attestorIds.length);

        for (uint256 i = 0; i < attestorIds.length; i++) {
            uint256 modelId = attestorIds[i];
            Attestation storage a = attestations[claimId][modelId];
            bytes32 archHash = keccak256(bytes(models[modelId].architecture));

            if (a.supportsClaim) {
                bool found = false;
                for (uint256 j = 0; j < forArchitectures; j++) {
                    if (seenFor[j] == archHash) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    seenFor[forArchitectures] = archHash;
                    forArchitectures++;
                }
            } else {
                bool found = false;
                for (uint256 j = 0; j < againstArchitectures; j++) {
                    if (seenAgainst[j] == archHash) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    seenAgainst[againstArchitectures] = archHash;
                    againstArchitectures++;
                }
            }
        }
    }
}

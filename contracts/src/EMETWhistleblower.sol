// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {IEMET} from "./interfaces/IEMET.sol";

/// @title EMETWhistleblower - Collusion detection and bounty system
/// @notice Allows anyone to submit evidence of collusion or manipulation.
///         Verified reports earn 10% of slashed funds as a bounty.
///         Supports ZK proofs for anonymous reporting.
///
///      Flow:
///        1. Reporter submits evidence (hash + optional ZK proof)
///        2. Verifier reviews evidence
///        3. If confirmed, slashed funds trigger bounty payment
///        4. Reporter receives 10% of slashed amount
///
/// @dev ZK proof verification is abstracted — a future verifier contract
///      can validate proofs. Current implementation uses a trusted verifier model.
contract EMETWhistleblower {
    // ============ Constants ============

    /// @notice EMET token on Base mainnet
    IEMET public constant EMET = IEMET(0x013c5C58EEe0d1B15e19504ca24AcF3E9c246A0C);

    /// @notice Bounty percentage in basis points (10% = 1000 bps)
    uint256 public constant BOUNTY_BPS = 1000;

    /// @notice Basis-point denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum evidence size (to prevent griefing)
    uint256 public constant MAX_EVIDENCE_LENGTH = 1000;

    // ============ Types ============

    enum ReportStatus {
        Pending,    // Submitted, awaiting review
        Verified,   // Evidence confirmed, bounty ready
        Rejected,   // Evidence insufficient
        Rewarded    // Bounty paid out
    }

    struct Report {
        address reporter;       // Reporter address (address(0) for anonymous ZK reports)
        bytes32 evidenceHash;   // keccak256 of evidence data
        string evidenceURI;     // IPFS/Arweave URI to detailed evidence
        bytes zkProof;          // Optional ZK proof for anonymous reports
        uint256 timestamp;      // When report was submitted
        ReportStatus status;    // Current status
        uint256 slashedAmount;  // Amount slashed from colluders (set on verification)
        uint256 bountyPaid;     // Bounty amount paid to reporter
        address[] colluders;    // Identified colluding addresses
    }

    // ============ State ============

    /// @notice All reports indexed by ID
    mapping(uint256 => Report) public reports;

    /// @notice Total number of reports
    uint256 public reportCount;

    /// @notice Authorized verifier (can confirm/reject reports)
    address public verifier;

    /// @notice Deployer, used to set verifier once
    address public immutable deployer;

    /// @notice Total bounties paid
    uint256 public totalBountiesPaid;

    /// @notice Total reports verified
    uint256 public totalVerifiedReports;

    /// @notice Reports per reporter (for tracking)
    mapping(address => uint256[]) public reporterHistory;

    /// @notice Whether an evidence hash has been submitted (prevent duplicates)
    mapping(bytes32 => bool) public evidenceSubmitted;

    /// @notice Optional ZK verifier contract for anonymous proofs
    address public zkVerifier;

    // ============ Events ============

    event ReportSubmitted(
        uint256 indexed reportId,
        address indexed reporter,
        bytes32 indexed evidenceHash,
        string evidenceURI,
        bool isAnonymous
    );

    event ReportVerified(
        uint256 indexed reportId,
        uint256 slashedAmount,
        address[] colluders
    );

    event ReportRejected(
        uint256 indexed reportId,
        string reason
    );

    event BountyPaid(
        uint256 indexed reportId,
        address indexed recipient,
        uint256 amount
    );

    event VerifierSet(address indexed verifier);
    event ZKVerifierSet(address indexed zkVerifier);

    // ============ Errors ============

    error OnlyVerifier();
    error OnlyDeployer();
    error VerifierAlreadySet();
    error ZeroAddress();
    error ReportDoesNotExist(uint256 reportId);
    error InvalidReportStatus(uint256 reportId, ReportStatus current, ReportStatus required);
    error DuplicateEvidence(bytes32 evidenceHash);
    error EmptyEvidence();
    error EvidenceTooLong();
    error TransferFailed();
    error BountyAlreadyPaid(uint256 reportId);
    error InsufficientFunds(uint256 required, uint256 available);
    error InvalidZKProof();
    error NoColludersSpecified();

    // ============ Constructor ============

    constructor() {
        deployer = msg.sender;
    }

    // ============ Configuration ============

    /// @notice Set the authorized verifier. Can only be set once.
    /// @param _verifier Address authorized to verify/reject reports
    function setVerifier(address _verifier) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (verifier != address(0)) revert VerifierAlreadySet();
        if (_verifier == address(0)) revert ZeroAddress();
        verifier = _verifier;
        emit VerifierSet(_verifier);
    }

    /// @notice Set optional ZK proof verifier contract
    /// @param _zkVerifier Address of the ZK verifier contract
    function setZKVerifier(address _zkVerifier) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (_zkVerifier == address(0)) revert ZeroAddress();
        zkVerifier = _zkVerifier;
        emit ZKVerifierSet(_zkVerifier);
    }

    // ============ Report Submission ============

    /// @notice Submit a report of collusion with evidence
    /// @param evidenceHash keccak256 hash of the evidence data
    /// @param evidenceURI URI to detailed evidence (IPFS/Arweave)
    /// @return reportId The unique ID of the submitted report
    function submitReport(bytes32 evidenceHash, string calldata evidenceURI)
        external
        returns (uint256 reportId)
    {
        if (evidenceHash == bytes32(0)) revert EmptyEvidence();
        if (bytes(evidenceURI).length == 0) revert EmptyEvidence();
        if (bytes(evidenceURI).length > MAX_EVIDENCE_LENGTH) revert EvidenceTooLong();
        if (evidenceSubmitted[evidenceHash]) revert DuplicateEvidence(evidenceHash);

        evidenceSubmitted[evidenceHash] = true;
        reportId = reportCount++;

        reports[reportId] = Report({
            reporter: msg.sender,
            evidenceHash: evidenceHash,
            evidenceURI: evidenceURI,
            zkProof: "",
            timestamp: block.timestamp,
            status: ReportStatus.Pending,
            slashedAmount: 0,
            bountyPaid: 0,
            colluders: new address[](0)
        });

        reporterHistory[msg.sender].push(reportId);

        emit ReportSubmitted(reportId, msg.sender, evidenceHash, evidenceURI, false);
    }

    /// @notice Submit an anonymous report with ZK proof
    /// @param evidenceHash keccak256 hash of the evidence data
    /// @param evidenceURI URI to detailed evidence
    /// @param proof ZK proof data for anonymous verification
    /// @param proofRecipient Address to receive bounty (can be a fresh address)
    /// @return reportId The unique ID of the submitted report
    function submitAnonymousReport(
        bytes32 evidenceHash,
        string calldata evidenceURI,
        bytes calldata proof,
        address proofRecipient
    ) external returns (uint256 reportId) {
        if (evidenceHash == bytes32(0)) revert EmptyEvidence();
        if (bytes(evidenceURI).length == 0) revert EmptyEvidence();
        if (bytes(evidenceURI).length > MAX_EVIDENCE_LENGTH) revert EvidenceTooLong();
        if (evidenceSubmitted[evidenceHash]) revert DuplicateEvidence(evidenceHash);
        if (proof.length == 0) revert InvalidZKProof();
        if (proofRecipient == address(0)) revert ZeroAddress();

        // Verify ZK proof if verifier is set
        if (zkVerifier != address(0)) {
            (bool success, bytes memory result) = zkVerifier.staticcall(
                abi.encodeWithSignature("verifyProof(bytes32,bytes)", evidenceHash, proof)
            );
            if (!success || (result.length > 0 && !abi.decode(result, (bool)))) {
                revert InvalidZKProof();
            }
        }

        evidenceSubmitted[evidenceHash] = true;
        reportId = reportCount++;

        reports[reportId] = Report({
            reporter: proofRecipient,  // Bounty goes to proof recipient
            evidenceHash: evidenceHash,
            evidenceURI: evidenceURI,
            zkProof: proof,
            timestamp: block.timestamp,
            status: ReportStatus.Pending,
            slashedAmount: 0,
            bountyPaid: 0,
            colluders: new address[](0)
        });

        emit ReportSubmitted(reportId, address(0), evidenceHash, evidenceURI, true);
    }

    // ============ Verification ============

    /// @notice Verify a report and record the slashed amount
    /// @param reportId The report to verify
    /// @param slashedAmount Total amount slashed from colluders
    /// @param colluders Array of identified colluding addresses
    function verifyReport(
        uint256 reportId,
        uint256 slashedAmount,
        address[] calldata colluders
    ) external {
        _onlyVerifier();
        if (reportId >= reportCount) revert ReportDoesNotExist(reportId);
        if (colluders.length == 0) revert NoColludersSpecified();

        Report storage report = reports[reportId];
        if (report.status != ReportStatus.Pending) {
            revert InvalidReportStatus(reportId, report.status, ReportStatus.Pending);
        }

        report.status = ReportStatus.Verified;
        report.slashedAmount = slashedAmount;
        report.colluders = colluders;
        totalVerifiedReports++;

        emit ReportVerified(reportId, slashedAmount, colluders);
    }

    /// @notice Reject a report
    /// @param reportId The report to reject
    /// @param reason Why the report was rejected
    function rejectReport(uint256 reportId, string calldata reason) external {
        _onlyVerifier();
        if (reportId >= reportCount) revert ReportDoesNotExist(reportId);

        Report storage report = reports[reportId];
        if (report.status != ReportStatus.Pending) {
            revert InvalidReportStatus(reportId, report.status, ReportStatus.Pending);
        }

        report.status = ReportStatus.Rejected;

        emit ReportRejected(reportId, reason);
    }

    // ============ Bounty Payment ============

    /// @notice Pay bounty for a verified report (10% of slashed funds)
    /// @dev Contract must hold sufficient EMET. Fund via direct transfer.
    /// @param reportId The verified report to pay bounty for
    function payBounty(uint256 reportId) external {
        if (reportId >= reportCount) revert ReportDoesNotExist(reportId);

        Report storage report = reports[reportId];
        if (report.status != ReportStatus.Verified) {
            revert InvalidReportStatus(reportId, report.status, ReportStatus.Verified);
        }
        if (report.bountyPaid > 0) revert BountyAlreadyPaid(reportId);

        uint256 bounty = (report.slashedAmount * BOUNTY_BPS) / BPS_DENOMINATOR;

        uint256 balance = EMET.balanceOf(address(this));
        if (balance < bounty) revert InsufficientFunds(bounty, balance);

        report.bountyPaid = bounty;
        report.status = ReportStatus.Rewarded;
        totalBountiesPaid += bounty;

        bool success = EMET.transfer(report.reporter, bounty);
        if (!success) revert TransferFailed();

        emit BountyPaid(reportId, report.reporter, bounty);
    }

    // ============ View Functions ============

    /// @notice Get full report details
    /// @param reportId The report ID
    /// @return reporter Reporter address
    /// @return evidenceHash Hash of evidence
    /// @return evidenceURI Evidence URI
    /// @return timestamp Submission time
    /// @return status Current status
    /// @return slashedAmount Amount slashed
    /// @return bountyPaid Bounty paid
    /// @return colluders Identified colluding addresses
    function getReport(uint256 reportId)
        external
        view
        returns (
            address reporter,
            bytes32 evidenceHash,
            string memory evidenceURI,
            uint256 timestamp,
            ReportStatus status,
            uint256 slashedAmount,
            uint256 bountyPaid,
            address[] memory colluders
        )
    {
        if (reportId >= reportCount) revert ReportDoesNotExist(reportId);
        Report storage r = reports[reportId];
        return (
            r.reporter,
            r.evidenceHash,
            r.evidenceURI,
            r.timestamp,
            r.status,
            r.slashedAmount,
            r.bountyPaid,
            r.colluders
        );
    }

    /// @notice Calculate expected bounty for a given slashed amount
    /// @param slashedAmount The amount that would be slashed
    /// @return bounty The expected bounty (10%)
    function calculateBounty(uint256 slashedAmount) external pure returns (uint256 bounty) {
        return (slashedAmount * BOUNTY_BPS) / BPS_DENOMINATOR;
    }

    /// @notice Get number of reports by a reporter
    /// @param reporter The reporter address
    /// @return count Number of reports submitted
    function getReporterReportCount(address reporter) external view returns (uint256 count) {
        return reporterHistory[reporter].length;
    }

    /// @notice Check if evidence has already been submitted
    /// @param evidenceHash The evidence hash to check
    /// @return submitted True if already submitted
    function isEvidenceSubmitted(bytes32 evidenceHash) external view returns (bool submitted) {
        return evidenceSubmitted[evidenceHash];
    }

    /// @notice Check if a report's ZK proof is present
    /// @param reportId The report to check
    /// @return hasProof True if ZK proof exists
    function hasZKProof(uint256 reportId) external view returns (bool hasProof) {
        if (reportId >= reportCount) return false;
        return reports[reportId].zkProof.length > 0;
    }

    // ============ Internal ============

    function _onlyVerifier() internal view {
        if (msg.sender != verifier) revert OnlyVerifier();
    }
}

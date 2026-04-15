// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "../../interfaces/IAgenticCommerce.sol";
import "./ITwoStageUnderwritingHookView.sol";
import "./TwoStageUnderwritingTypes.sol";

contract TwoStageUnderwritingEvaluator is EIP712 {
    error ZeroAddress();
    error WrongDecisionStatus();
    error WrongDecisionState();
    error DecisionExpired(uint64 deadline, uint64 currentTimestamp);
    error NonceUsed(address underwriter, uint256 nonce);
    error InvalidSigner(address expected, address actual);

    bytes32 private constant COMPLETE_TYPEHASH =
        keccak256("CompleteDecision(uint256 jobId,bytes32 reason,uint64 deadline,uint256 nonce)");
    bytes32 private constant REJECT_TYPEHASH =
        keccak256("RejectDecision(uint256 jobId,bytes32 reason,uint64 deadline,uint256 nonce)");

    IAgenticCommerce public immutable acp;
    ITwoStageUnderwritingHookView public immutable hook;

    mapping(address underwriter => mapping(uint256 nonce => bool used)) public usedNonces;

    constructor(address acpContract_, address hook_) EIP712("TwoStage Underwriting Evaluator", "1") {
        if (acpContract_ == address(0) || hook_ == address(0)) revert ZeroAddress();
        acp = IAgenticCommerce(acpContract_);
        hook = ITwoStageUnderwritingHookView(hook_);
    }

    function completeBySig(TwoStageUnderwritingTypes.CompleteDecision calldata decision, bytes calldata signature)
        external
    {
        if (block.timestamp > decision.deadline) revert DecisionExpired(decision.deadline, uint64(block.timestamp));

        IAgenticCommerce.Job memory job = acp.getJob(decision.jobId);
        if (job.status != IAgenticCommerce.JobStatus.Submitted) revert WrongDecisionStatus();
        if (hook.jobSidecarState(decision.jobId) != TwoStageUnderwritingTypes.SidecarState.EvidenceSubmitted) {
            revert WrongDecisionState();
        }

        _consumeNonceAndVerifySigner(
            hook.jobUnderwriter(decision.jobId),
            decision.nonce,
            _hashTypedDataV4(
                keccak256(abi.encode(COMPLETE_TYPEHASH, decision.jobId, decision.reason, decision.deadline, decision.nonce))
            ),
            signature
        );

        acp.complete(decision.jobId, decision.reason, "");
    }

    function rejectBySig(TwoStageUnderwritingTypes.RejectDecision calldata decision, bytes calldata signature)
        external
    {
        if (block.timestamp > decision.deadline) revert DecisionExpired(decision.deadline, uint64(block.timestamp));

        IAgenticCommerce.Job memory job = acp.getJob(decision.jobId);
        if (job.status != IAgenticCommerce.JobStatus.Submitted) revert WrongDecisionStatus();
        if (hook.jobSidecarState(decision.jobId) != TwoStageUnderwritingTypes.SidecarState.EvidenceSubmitted) {
            revert WrongDecisionState();
        }

        _consumeNonceAndVerifySigner(
            hook.jobUnderwriter(decision.jobId),
            decision.nonce,
            _hashTypedDataV4(
                keccak256(abi.encode(REJECT_TYPEHASH, decision.jobId, decision.reason, decision.deadline, decision.nonce))
            ),
            signature
        );

        acp.reject(decision.jobId, decision.reason, "");
    }

    function _consumeNonceAndVerifySigner(
        address expectedUnderwriter,
        uint256 nonce,
        bytes32 digest,
        bytes calldata signature
    ) internal {
        if (usedNonces[expectedUnderwriter][nonce]) revert NonceUsed(expectedUnderwriter, nonce);

        address recovered = ECDSA.recover(digest, signature);
        if (recovered != expectedUnderwriter || expectedUnderwriter == address(0)) {
            revert InvalidSigner(expectedUnderwriter, recovered);
        }

        usedNonces[expectedUnderwriter][nonce] = true;
    }
}

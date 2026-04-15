// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/IAgenticCommerce.sol";
import "./TwoStageUnderwritingTypes.sol";

abstract contract TwoStageUnderwritingWorkflowCore {
    error UnderwriterNotRegistered();
    error ProviderRequired();
    error EvaluatorMismatch();
    error ZeroAddress();
    error CommitExpired();
    error CommitLocked();
    error CommitNotFound();
    error ParentNotCommitted();
    error ParentNotAwaitingClose();
    error ActiveCloseExists();
    error ParentMismatch();
    error EvidenceMismatch();
    error InvalidState();

    mapping(address => bool) internal registeredUnderwriterByAddress;
    mapping(uint256 => TwoStageUnderwritingTypes.UnderwriteCommit) internal commits;
    mapping(uint256 => bytes32) internal commitHashByJobId;
    mapping(uint256 => address) internal committedPaymentTokenByJobId;
    mapping(uint256 => uint256) internal committedBudgetByJobId;
    mapping(uint256 => bool) internal awaitingCloseByJobId;
    mapping(uint256 => uint256) internal parentJobIdByCloseJobId;
    mapping(uint256 => uint256) internal activeCloseJobIdByParentJobId;
    mapping(uint256 => TwoStageUnderwritingTypes.SidecarState) internal sidecarStateByJobId;

    function _registerUnderwriter(address underwriter) internal {
        if (underwriter == address(0)) revert ZeroAddress();
        registeredUnderwriterByAddress[underwriter] = true;
    }

    function _unregisterUnderwriter(address underwriter) internal {
        if (underwriter == address(0)) revert ZeroAddress();
        delete registeredUnderwriterByAddress[underwriter];
    }

    function _isRegisteredUnderwriter(address underwriter) internal view returns (bool) {
        return registeredUnderwriterByAddress[underwriter];
    }

    function _getCommit(uint256 jobId) internal view returns (TwoStageUnderwritingTypes.UnderwriteCommit memory) {
        return commits[jobId];
    }

    function _isAwaitingClose(uint256 jobId) internal view returns (bool) {
        return awaitingCloseByJobId[jobId];
    }

    function _getParentJobId(uint256 closeJobId) internal view returns (uint256) {
        return parentJobIdByCloseJobId[closeJobId];
    }

    function _getActiveCloseJobId(uint256 parentJobId) internal view returns (uint256) {
        return activeCloseJobIdByParentJobId[parentJobId];
    }

    function _getSidecarState(uint256 jobId) internal view returns (TwoStageUnderwritingTypes.SidecarState) {
        return sidecarStateByJobId[jobId];
    }

    function _getSettlementJobId(uint256 jobId) internal view returns (uint256) {
        if (commitHashByJobId[jobId] == bytes32(0)) return 0;

        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = commits[jobId];
        if (commit.parentJobId != 0) {
            return commit.parentJobId;
        }

        return jobId;
    }

    function _getUnderwriter(uint256 jobId) internal view returns (address) {
        return _requireCommit(jobId).underwriter;
    }

    function _preSetBudgetWorkflow(
        IAgenticCommerce acp,
        address expectedEvaluator,
        uint256 jobId,
        address paymentToken,
        uint256 amount,
        bytes memory optParams
    ) internal {
        IAgenticCommerce.Job memory job = acp.getJob(jobId);
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit =
            abi.decode(optParams, (TwoStageUnderwritingTypes.UnderwriteCommit));
        bytes32 newCommitHash = keccak256(abi.encode(commit));

        if (job.provider == address(0)) revert ProviderRequired();
        if (job.evaluator != expectedEvaluator) revert EvaluatorMismatch();

        if (commitHashByJobId[jobId] != bytes32(0)) {
            if (commitHashByJobId[jobId] != newCommitHash) revert CommitLocked();
            if (committedPaymentTokenByJobId[jobId] != paymentToken) revert CommitLocked();
            if (committedBudgetByJobId[jobId] != amount) revert CommitLocked();
            return;
        }

        if (commit.validUntil <= block.timestamp) revert CommitExpired();

        if (commit.parentJobId == 0) {
            if (!registeredUnderwriterByAddress[commit.underwriter]) revert UnderwriterNotRegistered();
        } else {
            _clearStaleCloseIfTerminal(acp, commit.parentJobId);
            _validateCloseCommit(acp, jobId, job, commit);
            parentJobIdByCloseJobId[jobId] = commit.parentJobId;
            activeCloseJobIdByParentJobId[commit.parentJobId] = jobId;
        }

        commitHashByJobId[jobId] = newCommitHash;
        committedPaymentTokenByJobId[jobId] = paymentToken;
        committedBudgetByJobId[jobId] = amount;
        commits[jobId] = commit;
        sidecarStateByJobId[jobId] = TwoStageUnderwritingTypes.SidecarState.Committed;
    }

    function _preFundWorkflow(IAgenticCommerce acp, uint256 jobId) internal view {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _requireCommit(jobId);
        if (sidecarStateByJobId[jobId] != TwoStageUnderwritingTypes.SidecarState.Committed) revert InvalidState();
        if (commit.parentJobId != 0) _assertParentReadyForClose(acp, commit.parentJobId);
    }

    function _postFundWorkflow(uint256 jobId) internal {
        if (sidecarStateByJobId[jobId] != TwoStageUnderwritingTypes.SidecarState.Committed) revert InvalidState();
        sidecarStateByJobId[jobId] = TwoStageUnderwritingTypes.SidecarState.FeeEscrowed;
    }

    function _markProtectedWorkflow(uint256 jobId) internal {
        _requireCommit(jobId);
        if (sidecarStateByJobId[jobId] != TwoStageUnderwritingTypes.SidecarState.FeeEscrowed) revert InvalidState();
        sidecarStateByJobId[jobId] = TwoStageUnderwritingTypes.SidecarState.Protected;
    }

    function _preSubmitWorkflow(IAgenticCommerce acp, uint256 jobId) internal view {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _requireCommit(jobId);
        if (sidecarStateByJobId[jobId] != TwoStageUnderwritingTypes.SidecarState.Protected) revert InvalidState();
        if (commit.parentJobId != 0) _assertParentReadyForClose(acp, commit.parentJobId);
    }

    function _postSubmitWorkflow(uint256 jobId, bytes32 deliverable, bytes memory optParams) internal {
        if (sidecarStateByJobId[jobId] != TwoStageUnderwritingTypes.SidecarState.Protected) revert InvalidState();

        TwoStageUnderwritingTypes.SubmitEvidence memory evidence =
            abi.decode(optParams, (TwoStageUnderwritingTypes.SubmitEvidence));
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _requireCommit(jobId);

        if (deliverable != evidence.bundleHash) revert EvidenceMismatch();
        if (evidence.policyHash != commit.policyHash) revert EvidenceMismatch();
        if (evidence.quoteIdHash != commit.quoteIdHash) revert EvidenceMismatch();
        if (evidence.termsHash != commit.termsHash) revert EvidenceMismatch();

        sidecarStateByJobId[jobId] = TwoStageUnderwritingTypes.SidecarState.EvidenceSubmitted;
    }

    function _preDecisionWorkflow(IAgenticCommerce acp, uint256 jobId) internal view {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _requireCommit(jobId);
        if (sidecarStateByJobId[jobId] != TwoStageUnderwritingTypes.SidecarState.EvidenceSubmitted) revert InvalidState();
        if (commit.parentJobId != 0) _assertParentReadyForClose(acp, commit.parentJobId);
    }

    function _preRejectWorkflow(IAgenticCommerce acp, uint256 jobId) internal view {
        IAgenticCommerce.Job memory job = acp.getJob(jobId);
        if (job.status == IAgenticCommerce.JobStatus.Open) return;
        _preDecisionWorkflow(acp, jobId);
    }

    function _postCompleteWorkflow(uint256 jobId) internal {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _requireCommit(jobId);
        if (commit.parentJobId == 0 && commit.allowCloseJob) {
            awaitingCloseByJobId[jobId] = true;
            sidecarStateByJobId[jobId] = TwoStageUnderwritingTypes.SidecarState.AwaitingClose;
            return;
        }

        sidecarStateByJobId[jobId] = TwoStageUnderwritingTypes.SidecarState.SuccessPendingConfirmation;

        if (commit.parentJobId != 0) {
            uint256 parentJobId = commit.parentJobId;
            if (activeCloseJobIdByParentJobId[parentJobId] == jobId) {
                delete activeCloseJobIdByParentJobId[parentJobId];
            }
            delete awaitingCloseByJobId[parentJobId];
            sidecarStateByJobId[parentJobId] = TwoStageUnderwritingTypes.SidecarState.SuccessPendingConfirmation;
        }
    }

    function _postRejectWorkflow(uint256 jobId) internal {
        if (commitHashByJobId[jobId] == bytes32(0)) return;

        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = commits[jobId];
        sidecarStateByJobId[jobId] = TwoStageUnderwritingTypes.SidecarState.RejectSettled;

        if (commit.parentJobId != 0 && activeCloseJobIdByParentJobId[commit.parentJobId] == jobId) {
            delete activeCloseJobIdByParentJobId[commit.parentJobId];
        }
    }

    function _validateCloseCommit(
        IAgenticCommerce acp,
        uint256 jobId,
        IAgenticCommerce.Job memory job,
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit
    ) internal view {
        TwoStageUnderwritingTypes.UnderwriteCommit memory parentCommit = commits[commit.parentJobId];
        IAgenticCommerce.Job memory parentJob = acp.getJob(commit.parentJobId);
        uint256 activeCloseJobId = activeCloseJobIdByParentJobId[commit.parentJobId];

        if (commitHashByJobId[commit.parentJobId] == bytes32(0)) revert ParentNotCommitted();
        if (parentJob.id == 0) revert ParentMismatch();
        if (commit.parentJobId == jobId) revert ParentMismatch();
        if (parentCommit.parentJobId != 0 || !parentCommit.allowCloseJob || commit.allowCloseJob) {
            revert ParentMismatch();
        }
        if (
            parentJob.client != job.client || parentJob.provider != job.provider || parentJob.evaluator != job.evaluator
                || parentJob.hook != job.hook
        ) revert ParentMismatch();
        if (parentCommit.underwriter != commit.underwriter) revert ParentMismatch();
        _assertParentReadyForClose(acp, commit.parentJobId);
        if (activeCloseJobId != 0 && activeCloseJobId != jobId) revert ActiveCloseExists();
    }

    function _assertParentReadyForClose(IAgenticCommerce acp, uint256 parentJobId) internal view {
        IAgenticCommerce.Job memory parentJob = acp.getJob(parentJobId);
        if (
            parentJob.status != IAgenticCommerce.JobStatus.Completed
                || !awaitingCloseByJobId[parentJobId]
                || sidecarStateByJobId[parentJobId] != TwoStageUnderwritingTypes.SidecarState.AwaitingClose
        ) {
            revert ParentNotAwaitingClose();
        }
    }

    function _clearStaleCloseIfTerminal(IAgenticCommerce acp, uint256 parentJobId) internal {
        uint256 activeCloseJobId = activeCloseJobIdByParentJobId[parentJobId];
        if (activeCloseJobId == 0) return;

        IAgenticCommerce.Job memory activeCloseJob = acp.getJob(activeCloseJobId);
        if (
            activeCloseJob.status == IAgenticCommerce.JobStatus.Rejected
                || activeCloseJob.status == IAgenticCommerce.JobStatus.Cancelled
                || activeCloseJob.status == IAgenticCommerce.JobStatus.Expired
        ) {
            delete activeCloseJobIdByParentJobId[parentJobId];
        }
    }

    function _requireCommit(uint256 jobId) internal view returns (TwoStageUnderwritingTypes.UnderwriteCommit memory) {
        if (commitHashByJobId[jobId] == bytes32(0)) revert CommitNotFound();
        return commits[jobId];
    }
}

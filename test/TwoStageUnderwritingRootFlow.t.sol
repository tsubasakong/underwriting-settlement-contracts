// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/interfaces/IAgenticCommerce.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingHook.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingTypes.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingWorkflowCore.sol";
import "./utils/TwoStageUnderwritingTestBase.sol";

contract TwoStageUnderwritingRootFlowTest is TwoStageUnderwritingTestBase {
    function test_completeBySig_marksParentAwaitingCloseAndConsumesNonce() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(true);

        _commitJob(ROOT_JOB_ID, commit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        _protect(ROOT_JOB_ID);
        _submitEvidence(ROOT_JOB_ID, commit);
        _completeBySig(ROOT_JOB_ID, bytes32("complete"), uint64(block.timestamp + 1 days), 41);

        assertEq(uint256(acp.getJob(ROOT_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Completed));
        assertTrue(hook.isAwaitingClose(ROOT_JOB_ID));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.AwaitingClose)
        );
        assertTrue(evaluator.usedNonces(underwriter, 41));
    }

    function test_rejectBySig_setsRejectSettledAndConsumesNonce() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(false);

        _commitJob(ROOT_JOB_ID, commit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        _protect(ROOT_JOB_ID);
        _submitEvidence(ROOT_JOB_ID, commit);
        _rejectBySig(ROOT_JOB_ID, bytes32("reject"), uint64(block.timestamp + 1 days), 51);

        assertEq(uint256(acp.getJob(ROOT_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Rejected));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.RejectSettled)
        );
        assertTrue(evaluator.usedNonces(underwriter, 51));
    }

    function test_submitEvidence_revertsWhenTermsMismatch() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(false);
        TwoStageUnderwritingTypes.SubmitEvidence memory evidence = TwoStageUnderwritingTypes.SubmitEvidence({
            bundleHash: keccak256("bundle"),
            policyHash: commit.policyHash,
            quoteIdHash: commit.quoteIdHash,
            termsHash: keccak256("different-terms")
        });

        _commitJob(ROOT_JOB_ID, commit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        _protect(ROOT_JOB_ID);

        vm.expectRevert(TwoStageUnderwritingWorkflowCore.EvidenceMismatch.selector);
        acp.runSubmit(hook, ROOT_JOB_ID, PROVIDER, evidence.bundleHash, abi.encode(evidence));
        assertEq(uint256(acp.getJob(ROOT_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Funded));
    }
}

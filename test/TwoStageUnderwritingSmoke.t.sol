// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/interfaces/IAgenticCommerce.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingHook.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingTypes.sol";
import "./mocks/MockAgenticCommerce.sol";
import "./utils/TwoStageUnderwritingTestBase.sol";

contract TwoStageUnderwritingSmokeTest is TwoStageUnderwritingTestBase {
    function test_rootWorkflow_advancesThroughProtection() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(true);

        _commitJob(ROOT_JOB_ID, commit);
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.Committed)
        );

        _fundToFeeEscrowed(ROOT_JOB_ID);
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.FeeEscrowed)
        );

        _protect(ROOT_JOB_ID);

        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.Protected)
        );
        assertEq(hook.jobSettlementJobId(ROOT_JOB_ID), ROOT_JOB_ID);
    }

    function test_onlyEvaluatorMayRelayCompletionAfterEvidenceSubmission() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(true);

        _commitJob(ROOT_JOB_ID, commit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        _protect(ROOT_JOB_ID);
        _submitEvidence(ROOT_JOB_ID, commit);

        vm.expectRevert(MockAgenticCommerce.UnauthorizedCompleteCaller.selector);
        acp.complete(ROOT_JOB_ID, bytes32("bad"), "");

        _completeBySig(ROOT_JOB_ID, bytes32("ok"), uint64(block.timestamp + 1 days), 11);

        assertEq(uint256(acp.getJob(ROOT_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Completed));
        assertTrue(hook.isAwaitingClose(ROOT_JOB_ID));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.AwaitingClose)
        );
    }

    function test_hookBeforeComplete_requiresEvaluatorCaller() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(true);
        bytes4 selector = bytes4(keccak256("complete(uint256,bytes32,bytes)"));
        bytes memory data = abi.encode(address(0xBAD), bytes32("bad"), bytes(""));

        _commitJob(ROOT_JOB_ID, commit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        _protect(ROOT_JOB_ID);
        _submitEvidence(ROOT_JOB_ID, commit);

        vm.expectRevert(TwoStageUnderwritingHook.OnlyEvaluator.selector);
        acp.callBeforeAction(hook, ROOT_JOB_ID, selector, data);
    }

    function test_onlyClientMayRejectCommittedOpenJob() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(true);
        bytes32 reason = bytes32("nope");

        _commitJob(ROOT_JOB_ID, commit);

        vm.expectRevert(MockAgenticCommerce.UnauthorizedRejectCaller.selector);
        acp.reject(ROOT_JOB_ID, reason, "");

        vm.prank(CLIENT);
        acp.reject(ROOT_JOB_ID, reason, "");

        assertEq(uint256(acp.getJob(ROOT_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Rejected));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.RejectSettled)
        );
    }

    function test_hookBeforeReject_requiresClientCallerForCommittedOpenJob() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(true);
        bytes4 selector = bytes4(keccak256("reject(uint256,bytes32,bytes)"));
        bytes memory data = abi.encode(address(0xBAD), bytes32("bad"), bytes(""));

        _commitJob(ROOT_JOB_ID, commit);

        vm.expectRevert(TwoStageUnderwritingHook.OnlyClient.selector);
        acp.callBeforeAction(hook, ROOT_JOB_ID, selector, data);
    }

    function test_cancelledActiveCloseSlot_canBeReplaced() public {
        _completeRootToAwaitingClose();
        _setJob(CLOSE_JOB_ID, "close", IAgenticCommerce.JobStatus.Open);
        _setJob(REPLACEMENT_CLOSE_JOB_ID, "replacement-close", IAgenticCommerce.JobStatus.Open);

        TwoStageUnderwritingTypes.UnderwriteCommit memory closeCommit =
            _closeCommit(ROOT_JOB_ID, underwriter, keccak256("close-terms"));

        _commitJob(CLOSE_JOB_ID, closeCommit);
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), CLOSE_JOB_ID);

        acp.setJobStatus(CLOSE_JOB_ID, IAgenticCommerce.JobStatus.Cancelled);

        _commitJob(REPLACEMENT_CLOSE_JOB_ID, closeCommit);
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), REPLACEMENT_CLOSE_JOB_ID);
        assertEq(hook.getParentJobId(REPLACEMENT_CLOSE_JOB_ID), ROOT_JOB_ID);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/interfaces/IAgenticCommerce.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingWorkflowCore.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingTypes.sol";
import "./utils/TwoStageUnderwritingTestBase.sol";

contract TwoStageUnderwritingCloseFlowTest is TwoStageUnderwritingTestBase {
    function test_closeCommit_requiresMatchingActorsAndUnderwriter() public {
        _completeRootToAwaitingClose();

        _setCustomJob(
            CLOSE_JOB_ID,
            CLIENT,
            address(0xBAD),
            address(evaluator),
            address(hook),
            "close",
            IAgenticCommerce.JobStatus.Open
        );

        vm.expectRevert(TwoStageUnderwritingWorkflowCore.ParentMismatch.selector);
        _commitJob(CLOSE_JOB_ID, _closeCommit(ROOT_JOB_ID, underwriter, keccak256("close-terms")));

        _setJob(CLOSE_JOB_ID, "close", IAgenticCommerce.JobStatus.Open);
        vm.expectRevert(TwoStageUnderwritingWorkflowCore.ParentMismatch.selector);
        _commitJob(CLOSE_JOB_ID, _closeCommit(ROOT_JOB_ID, address(0xBADF00D), keccak256("close-terms")));
    }

    function test_successfulClose_clearsParentLinkageAndUsesParentSettlementIdentity() public {
        _completeRootToAwaitingClose();
        _setJob(CLOSE_JOB_ID, "close", IAgenticCommerce.JobStatus.Open);

        TwoStageUnderwritingTypes.UnderwriteCommit memory closeCommit =
            _closeCommit(ROOT_JOB_ID, underwriter, keccak256("close-terms"));

        _commitJob(CLOSE_JOB_ID, closeCommit);
        _fundToFeeEscrowed(CLOSE_JOB_ID);
        _protect(CLOSE_JOB_ID);
        _submitEvidence(CLOSE_JOB_ID, closeCommit);
        _completeBySig(CLOSE_JOB_ID, bytes32("close"), uint64(block.timestamp + 1 days), 77);

        assertEq(uint256(acp.getJob(CLOSE_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Completed));
        assertEq(hook.jobSettlementJobId(CLOSE_JOB_ID), ROOT_JOB_ID);
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), 0);
        assertEq(hook.getParentJobId(CLOSE_JOB_ID), ROOT_JOB_ID);
        assertFalse(hook.isAwaitingClose(ROOT_JOB_ID));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.SuccessPendingConfirmation)
        );
        assertEq(
            uint256(hook.jobSidecarState(CLOSE_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.SuccessPendingConfirmation)
        );
    }
}

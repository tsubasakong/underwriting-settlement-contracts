// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/interfaces/IAgenticCommerce.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingTypes.sol";
import "./utils/TwoStageUnderwritingTestBase.sol";

contract TwoStageUnderwritingRecoveryTest is TwoStageUnderwritingTestBase {
    function test_closeReject_clearsOnlyActiveCloseSlot() public {
        _completeRootToAwaitingClose();
        _setJob(CLOSE_JOB_ID, "close", IAgenticCommerce.JobStatus.Open);

        TwoStageUnderwritingTypes.UnderwriteCommit memory closeCommit =
            _closeCommit(ROOT_JOB_ID, underwriter, keccak256("close-terms"));

        _commitJob(CLOSE_JOB_ID, closeCommit);
        _fundToFeeEscrowed(CLOSE_JOB_ID);
        _protect(CLOSE_JOB_ID);
        _submitEvidence(CLOSE_JOB_ID, closeCommit);
        _rejectBySig(CLOSE_JOB_ID, bytes32("close-reject"), uint64(block.timestamp + 1 days), 91);

        assertEq(uint256(acp.getJob(CLOSE_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Rejected));
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), 0);
        assertTrue(hook.isAwaitingClose(ROOT_JOB_ID));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.AwaitingClose)
        );
        assertEq(
            uint256(hook.jobSidecarState(CLOSE_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.RejectSettled)
        );
    }

    function test_expiredClose_canBeReplacedOnNextCommit() public {
        _completeRootToAwaitingClose();
        _setJob(CLOSE_JOB_ID, "close", IAgenticCommerce.JobStatus.Open);
        _setJob(REPLACEMENT_CLOSE_JOB_ID, "replacement-close", IAgenticCommerce.JobStatus.Open);

        TwoStageUnderwritingTypes.UnderwriteCommit memory closeCommit =
            _closeCommit(ROOT_JOB_ID, underwriter, keccak256("close-terms"));

        _commitJob(CLOSE_JOB_ID, closeCommit);
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), CLOSE_JOB_ID);

        acp.setJobStatus(CLOSE_JOB_ID, IAgenticCommerce.JobStatus.Expired);

        _commitJob(REPLACEMENT_CLOSE_JOB_ID, closeCommit);
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), REPLACEMENT_CLOSE_JOB_ID);
        assertEq(hook.getParentJobId(REPLACEMENT_CLOSE_JOB_ID), ROOT_JOB_ID);
    }
}

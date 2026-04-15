// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/IAgenticCommerce.sol";
import "./TwoStageUnderwritingHook.sol";
import "./TwoStageUnderwritingTypes.sol";

contract TwoStageUnderwritingCoordinator {
    error ZeroAddress();
    error WrongHook();
    error WrongJobStatus();
    error InvalidState();

    IAgenticCommerce public immutable acp;
    TwoStageUnderwritingHook public immutable hook;

    event FundingOrchestrated(uint256 indexed jobId, uint256 indexed settlementJobId);

    constructor(address acpContract_, address hook_) {
        if (acpContract_ == address(0) || hook_ == address(0)) revert ZeroAddress();
        acp = IAgenticCommerce(acpContract_);
        hook = TwoStageUnderwritingHook(hook_);
    }

    function orchestrateFunding(uint256 jobId) external {
        IAgenticCommerce.Job memory job = acp.getJob(jobId);
        if (job.hook != address(hook)) revert WrongHook();
        if (job.status != IAgenticCommerce.JobStatus.Funded) revert WrongJobStatus();
        if (hook.jobSidecarState(jobId) != TwoStageUnderwritingTypes.SidecarState.FeeEscrowed) revert InvalidState();

        hook.markProtected(jobId);
        emit FundingOrchestrated(jobId, hook.jobSettlementJobId(jobId));
    }
}

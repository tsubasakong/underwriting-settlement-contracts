// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TwoStageUnderwritingTypes.sol";

interface ITwoStageUnderwritingHookView {
    function getCommit(uint256 jobId) external view returns (TwoStageUnderwritingTypes.UnderwriteCommit memory);
    function jobUnderwriter(uint256 jobId) external view returns (address);
    function jobSidecarState(uint256 jobId) external view returns (TwoStageUnderwritingTypes.SidecarState);
    function jobSettlementJobId(uint256 jobId) external view returns (uint256);
    function isAwaitingClose(uint256 jobId) external view returns (bool);
    function getParentJobId(uint256 closeJobId) external view returns (uint256);
    function getActiveCloseJobId(uint256 parentJobId) external view returns (uint256);
}

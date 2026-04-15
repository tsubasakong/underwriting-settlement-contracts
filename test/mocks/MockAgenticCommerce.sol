// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../contracts/interfaces/IACPHook.sol";
import "../../contracts/interfaces/IAgenticCommerce.sol";

contract MockAgenticCommerce is IAgenticCommerce {
    error UnauthorizedCompleteCaller();
    error UnauthorizedRejectCaller();

    mapping(uint256 jobId => Job) internal jobs;
    mapping(uint256 jobId => address) internal completionCallerByJobId;
    mapping(uint256 jobId => address) internal openRejectCallerByJobId;

    function setJob(Job memory job) external {
        jobs[job.id] = job;
    }

    function setDecisionCallers(uint256 jobId, address completionCaller, address openRejectCaller) external {
        completionCallerByJobId[jobId] = completionCaller;
        openRejectCallerByJobId[jobId] = openRejectCaller;
    }

    function setJobStatus(uint256 jobId, JobStatus status) external {
        jobs[jobId].status = status;
    }

    function getJob(uint256 jobId) external view returns (Job memory) {
        return jobs[jobId];
    }

    function callBeforeAction(IACPHook hook, uint256 jobId, bytes4 selector, bytes memory data) external {
        hook.beforeAction(jobId, selector, data);
    }

    function callAfterAction(IACPHook hook, uint256 jobId, bytes4 selector, bytes memory data) external {
        hook.afterAction(jobId, selector, data);
    }

    function runSetBudget(IACPHook hook, uint256 jobId, address caller, address token, uint256 amount, bytes memory optParams)
        external
    {
        bytes4 selector = bytes4(keccak256("setBudget(uint256,address,uint256,bytes)"));
        bytes memory data = abi.encode(caller, token, amount, optParams);

        hook.beforeAction(jobId, selector, data);
        hook.afterAction(jobId, selector, data);
    }

    function runFund(IACPHook hook, uint256 jobId, address caller, bytes memory optParams) external {
        bytes4 selector = bytes4(keccak256("fund(uint256,uint256,bytes)"));
        bytes memory data = abi.encode(caller, optParams);

        hook.beforeAction(jobId, selector, data);
        jobs[jobId].status = JobStatus.Funded;
        hook.afterAction(jobId, selector, data);
    }

    function runSubmit(IACPHook hook, uint256 jobId, address caller, bytes32 deliverable, bytes memory optParams) external {
        bytes4 selector = bytes4(keccak256("submit(uint256,bytes32,bytes)"));
        bytes memory data = abi.encode(caller, deliverable, optParams);

        hook.beforeAction(jobId, selector, data);
        jobs[jobId].status = JobStatus.Submitted;
        hook.afterAction(jobId, selector, data);
    }

    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external {
        Job storage job = jobs[jobId];
        if (msg.sender != completionCallerByJobId[jobId]) revert UnauthorizedCompleteCaller();

        if (job.hook != address(0)) {
            IACPHook(job.hook).beforeAction(
                jobId, bytes4(keccak256("complete(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams)
            );
        }

        job.status = JobStatus.Completed;

        if (job.hook != address(0)) {
            IACPHook(job.hook).afterAction(jobId, bytes4(keccak256("complete(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams));
        }
    }

    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external {
        Job storage job = jobs[jobId];
        if (job.status == JobStatus.Open) {
            if (msg.sender != openRejectCallerByJobId[jobId]) revert UnauthorizedRejectCaller();
        } else if (msg.sender != completionCallerByJobId[jobId]) {
            revert UnauthorizedRejectCaller();
        }

        if (job.hook != address(0)) {
            IACPHook(job.hook).beforeAction(
                jobId, bytes4(keccak256("reject(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams)
            );
        }

        job.status = JobStatus.Rejected;

        if (job.hook != address(0)) {
            IACPHook(job.hook).afterAction(jobId, bytes4(keccak256("reject(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams));
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../contracts/interfaces/IACPHook.sol";
import "../../contracts/interfaces/IAgenticCommerce.sol";

contract MockAgenticCommerce is IAgenticCommerce {
    mapping(uint256 jobId => Job) internal jobs;

    function setJob(Job memory job) external {
        jobs[job.id] = job;
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

    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external {
        Job storage job = jobs[jobId];

        if (job.hook != address(0)) {
            IACPHook(job.hook).beforeAction(jobId, bytes4(keccak256("complete(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams));
        }

        job.status = JobStatus.Completed;

        if (job.hook != address(0)) {
            IACPHook(job.hook).afterAction(jobId, bytes4(keccak256("complete(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams));
        }
    }

    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external {
        Job storage job = jobs[jobId];

        if (job.hook != address(0)) {
            IACPHook(job.hook).beforeAction(jobId, bytes4(keccak256("reject(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams));
        }

        job.status = JobStatus.Rejected;

        if (job.hook != address(0)) {
            IACPHook(job.hook).afterAction(jobId, bytes4(keccak256("reject(uint256,bytes32,bytes)")), abi.encode(msg.sender, reason, optParams));
        }
    }
}

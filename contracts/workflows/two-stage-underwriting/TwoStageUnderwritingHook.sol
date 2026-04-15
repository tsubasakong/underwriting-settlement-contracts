// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../../interfaces/IACPHook.sol";
import "../../interfaces/IAgenticCommerce.sol";
import "./ITwoStageUnderwritingHookView.sol";
import "./TwoStageUnderwritingTypes.sol";
import "./TwoStageUnderwritingWorkflowCore.sol";

interface ITwoStageUnderwritingWiringTarget {
    function acp() external view returns (address);
    function hook() external view returns (address);
}

contract TwoStageUnderwritingHook is ERC165, IACPHook, ITwoStageUnderwritingHookView, TwoStageUnderwritingWorkflowCore {
    error OnlyACPContract();
    error OnlyAdmin();
    error OnlyClient();
    error OnlyCoordinator();
    error OnlyEvaluator();
    error WiringAlreadySet();
    error WiringIncomplete();
    error InvalidWiring();

    IAgenticCommerce public immutable acp;
    address public immutable admin;
    address public evaluator;
    address public coordinator;

    bytes4 private constant SEL_SET_BUDGET =
        bytes4(keccak256("setBudget(uint256,address,uint256,bytes)"));
    bytes4 private constant SEL_FUND =
        bytes4(keccak256("fund(uint256,uint256,bytes)"));
    bytes4 private constant SEL_SUBMIT =
        bytes4(keccak256("submit(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_COMPLETE =
        bytes4(keccak256("complete(uint256,bytes32,bytes)"));
    bytes4 private constant SEL_REJECT =
        bytes4(keccak256("reject(uint256,bytes32,bytes)"));

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier onlyCoordinator() {
        if (msg.sender != coordinator) revert OnlyCoordinator();
        _;
    }

    modifier onlyACP() {
        if (msg.sender != address(acp)) revert OnlyACPContract();
        _;
    }

    constructor(address acpContract_, address admin_) {
        if (acpContract_ == address(0) || admin_ == address(0)) revert ZeroAddress();
        acp = IAgenticCommerce(acpContract_);
        admin = admin_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IACPHook).interfaceId || super.supportsInterface(interfaceId);
    }

    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external override onlyACP {
        if (selector == SEL_SET_BUDGET) {
            (address caller, address token, uint256 amount, bytes memory optParams) =
                abi.decode(data, (address, address, uint256, bytes));
            _preSetBudget(jobId, caller, token, amount, optParams);
        } else if (selector == SEL_FUND) {
            (address caller, bytes memory optParams) = abi.decode(data, (address, bytes));
            _preFund(jobId, caller, optParams);
        } else if (selector == SEL_SUBMIT) {
            (address caller, bytes32 deliverable, bytes memory optParams) =
                abi.decode(data, (address, bytes32, bytes));
            _preSubmit(jobId, caller, deliverable, optParams);
        } else if (selector == SEL_COMPLETE) {
            (address caller, bytes32 reason, bytes memory optParams) =
                abi.decode(data, (address, bytes32, bytes));
            _preComplete(jobId, caller, reason, optParams);
        } else if (selector == SEL_REJECT) {
            (address caller, bytes32 reason, bytes memory optParams) =
                abi.decode(data, (address, bytes32, bytes));
            _preReject(jobId, caller, reason, optParams);
        }
    }

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external override onlyACP {
        if (selector == SEL_SET_BUDGET) {
            (address caller, address token, uint256 amount, bytes memory optParams) =
                abi.decode(data, (address, address, uint256, bytes));
            _postSetBudget(jobId, caller, token, amount, optParams);
        } else if (selector == SEL_FUND) {
            (address caller, bytes memory optParams) = abi.decode(data, (address, bytes));
            _postFund(jobId, caller, optParams);
        } else if (selector == SEL_SUBMIT) {
            (address caller, bytes32 deliverable, bytes memory optParams) =
                abi.decode(data, (address, bytes32, bytes));
            _postSubmit(jobId, caller, deliverable, optParams);
        } else if (selector == SEL_COMPLETE) {
            (address caller, bytes32 reason, bytes memory optParams) =
                abi.decode(data, (address, bytes32, bytes));
            _postComplete(jobId, caller, reason, optParams);
        } else if (selector == SEL_REJECT) {
            (address caller, bytes32 reason, bytes memory optParams) =
                abi.decode(data, (address, bytes32, bytes));
            _postReject(jobId, caller, reason, optParams);
        }
    }

    function setWiring(address evaluator_, address coordinator_) external onlyAdmin {
        if (evaluator != address(0) || coordinator != address(0)) revert WiringAlreadySet();
        if (evaluator_ == address(0) || coordinator_ == address(0)) revert ZeroAddress();

        _assertWiringTarget(evaluator_);
        _assertWiringTarget(coordinator_);

        evaluator = evaluator_;
        coordinator = coordinator_;
    }

    function registerUnderwriter(address underwriter) external onlyAdmin {
        _registerUnderwriter(underwriter);
    }

    function unregisterUnderwriter(address underwriter) external onlyAdmin {
        _unregisterUnderwriter(underwriter);
    }

    function markProtected(uint256 jobId) external onlyCoordinator {
        _markProtectedWorkflow(jobId);
    }

    function registeredUnderwriters(address underwriter) external view returns (bool) {
        return _isRegisteredUnderwriter(underwriter);
    }

    function getCommit(uint256 jobId) external view returns (TwoStageUnderwritingTypes.UnderwriteCommit memory) {
        return _getCommit(jobId);
    }

    function jobUnderwriter(uint256 jobId) external view returns (address) {
        return _getUnderwriter(jobId);
    }

    function jobSidecarState(uint256 jobId) external view returns (TwoStageUnderwritingTypes.SidecarState) {
        return _getSidecarState(jobId);
    }

    function jobSettlementJobId(uint256 jobId) external view returns (uint256) {
        return _getSettlementJobId(jobId);
    }

    function isAwaitingClose(uint256 jobId) external view returns (bool) {
        return _isAwaitingClose(jobId);
    }

    function getParentJobId(uint256 closeJobId) external view returns (uint256) {
        return _getParentJobId(closeJobId);
    }

    function getActiveCloseJobId(uint256 parentJobId) external view returns (uint256) {
        return _getActiveCloseJobId(parentJobId);
    }

    function _preSetBudget(uint256 jobId, address, address token, uint256 amount, bytes memory optParams) internal {
        _requireWiring();
        _preSetBudgetWorkflow(acp, evaluator, jobId, token, amount, optParams);
    }

    function _postSetBudget(uint256, address, address, uint256, bytes memory) internal pure {}

    function _preFund(uint256 jobId, address, bytes memory) internal view {
        _preFundWorkflow(acp, jobId);
    }

    function _postFund(uint256 jobId, address, bytes memory) internal {
        _postFundWorkflow(jobId);
    }

    function _preSubmit(uint256 jobId, address, bytes32, bytes memory) internal view {
        _preSubmitWorkflow(acp, jobId);
    }

    function _postSubmit(uint256 jobId, address, bytes32 deliverable, bytes memory optParams) internal {
        _postSubmitWorkflow(jobId, deliverable, optParams);
    }

    function _preComplete(uint256 jobId, address caller, bytes32, bytes memory) internal view {
        _requireEvaluatorCaller(caller);
        _preDecisionWorkflow(acp, jobId);
    }

    function _postComplete(uint256 jobId, address, bytes32, bytes memory) internal {
        _postCompleteWorkflow(jobId);
    }

    function _preReject(uint256 jobId, address caller, bytes32, bytes memory) internal view {
        IAgenticCommerce.Job memory job = acp.getJob(jobId);
        if (job.status == IAgenticCommerce.JobStatus.Open) {
            if (commitHashByJobId[jobId] != bytes32(0) && caller != job.client) revert OnlyClient();
        } else {
            _requireEvaluatorCaller(caller);
        }
        _preRejectWorkflow(acp, jobId);
    }

    function _postReject(uint256 jobId, address, bytes32, bytes memory) internal {
        _postRejectWorkflow(jobId);
    }

    function _requireWiring() internal view {
        if (evaluator == address(0) || coordinator == address(0)) revert WiringIncomplete();
    }

    function _requireEvaluatorCaller(address caller) internal view {
        if (caller != evaluator) revert OnlyEvaluator();
    }

    function _assertWiringTarget(address target) internal view {
        ITwoStageUnderwritingWiringTarget wiringTarget = ITwoStageUnderwritingWiringTarget(target);

        try wiringTarget.acp() returns (address targetAcp) {
            if (targetAcp != address(acp)) revert InvalidWiring();
        } catch {
            revert InvalidWiring();
        }

        try wiringTarget.hook() returns (address targetHook) {
            if (targetHook != address(this)) revert InvalidWiring();
        } catch {
            revert InvalidWiring();
        }
    }
}

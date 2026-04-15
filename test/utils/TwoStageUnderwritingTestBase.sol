// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/interfaces/IAgenticCommerce.sol";
import "../../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingCoordinator.sol";
import "../../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingEvaluator.sol";
import "../../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingHook.sol";
import "../../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingTypes.sol";
import "../mocks/MockAgenticCommerce.sol";

abstract contract TwoStageUnderwritingTestBase is Test {
    uint256 internal constant ROOT_JOB_ID = 1;
    uint256 internal constant CLOSE_JOB_ID = 2;
    uint256 internal constant REPLACEMENT_CLOSE_JOB_ID = 3;
    uint256 internal constant AMOUNT = 1 ether;
    uint256 internal constant UNDERWRITER_PK = 0xA11CE;

    address internal constant CLIENT = address(0xCA11);
    address internal constant PROVIDER = address(0xBEEF);
    address internal constant PAYMENT_TOKEN = address(0xC0FFEE);

    bytes32 internal constant COMPLETE_TYPEHASH =
        keccak256("CompleteDecision(uint256 jobId,bytes32 reason,uint64 deadline,uint256 nonce)");
    bytes32 internal constant REJECT_TYPEHASH =
        keccak256("RejectDecision(uint256 jobId,bytes32 reason,uint64 deadline,uint256 nonce)");
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    MockAgenticCommerce internal acp;
    TwoStageUnderwritingHook internal hook;
    TwoStageUnderwritingEvaluator internal evaluator;
    TwoStageUnderwritingCoordinator internal coordinator;
    address internal underwriter;

    function setUp() public virtual {
        underwriter = vm.addr(UNDERWRITER_PK);
        acp = new MockAgenticCommerce();
        hook = new TwoStageUnderwritingHook(address(acp), address(this));
        evaluator = new TwoStageUnderwritingEvaluator(address(acp), address(hook));
        coordinator = new TwoStageUnderwritingCoordinator(address(acp), address(hook));

        hook.setWiring(address(evaluator), address(coordinator));
        hook.registerUnderwriter(underwriter);

        _setJob(ROOT_JOB_ID, "root", IAgenticCommerce.JobStatus.Open);
    }

    function _rootCommit(bool allowCloseJob) internal view returns (TwoStageUnderwritingTypes.UnderwriteCommit memory) {
        return TwoStageUnderwritingTypes.UnderwriteCommit({
            parentJobId: 0,
            underwriter: underwriter,
            validUntil: uint64(block.timestamp + 1 days),
            policyHash: keccak256("policy"),
            quoteIdHash: keccak256("quote"),
            termsHash: keccak256("terms"),
            allowCloseJob: allowCloseJob
        });
    }

    function _closeCommit(uint256 parentJobId, address commitUnderwriter, bytes32 termsHash)
        internal
        view
        returns (TwoStageUnderwritingTypes.UnderwriteCommit memory)
    {
        return TwoStageUnderwritingTypes.UnderwriteCommit({
            parentJobId: parentJobId,
            underwriter: commitUnderwriter,
            validUntil: uint64(block.timestamp + 1 days),
            policyHash: keccak256("policy"),
            quoteIdHash: keccak256("quote"),
            termsHash: termsHash,
            allowCloseJob: false
        });
    }

    function _setJob(uint256 jobId, string memory description, IAgenticCommerce.JobStatus status) internal {
        _setCustomJob(jobId, CLIENT, PROVIDER, address(evaluator), address(hook), description, status);
    }

    function _setCustomJob(
        uint256 jobId,
        address client,
        address provider,
        address evaluatorAddress,
        address hookAddress,
        string memory description,
        IAgenticCommerce.JobStatus status
    ) internal {
        acp.setJob(
            IAgenticCommerce.Job({
                id: jobId,
                client: client,
                provider: provider,
                evaluator: evaluatorAddress,
                description: description,
                budget: 0,
                expiredAt: block.timestamp + 1 days,
                status: status,
                hook: hookAddress,
                paymentToken: PAYMENT_TOKEN,
                providerAgentId: 0
            })
        );
        acp.setDecisionCallers(jobId, address(evaluator), client);
    }

    function _commitJob(uint256 jobId, TwoStageUnderwritingTypes.UnderwriteCommit memory commit) internal {
        acp.runSetBudget(hook, jobId, CLIENT, PAYMENT_TOKEN, AMOUNT, abi.encode(commit));
    }

    function _fundToFeeEscrowed(uint256 jobId) internal {
        acp.runFund(hook, jobId, CLIENT, "");
    }

    function _protect(uint256 jobId) internal {
        coordinator.orchestrateFunding(jobId);
    }

    function _submitEvidence(uint256 jobId, TwoStageUnderwritingTypes.UnderwriteCommit memory commit) internal {
        TwoStageUnderwritingTypes.SubmitEvidence memory evidence = TwoStageUnderwritingTypes.SubmitEvidence({
            bundleHash: keccak256("bundle"),
            policyHash: commit.policyHash,
            quoteIdHash: commit.quoteIdHash,
            termsHash: commit.termsHash
        });
        acp.runSubmit(hook, jobId, PROVIDER, evidence.bundleHash, abi.encode(evidence));
    }

    function _completeBySig(uint256 jobId, bytes32 reason, uint64 deadline, uint256 nonce) internal {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(UNDERWRITER_PK, _completeDecisionDigest(jobId, reason, deadline, nonce));
        bytes memory signature = abi.encodePacked(r, s, v);

        evaluator.completeBySig(
            TwoStageUnderwritingTypes.CompleteDecision({
                jobId: jobId,
                reason: reason,
                deadline: deadline,
                nonce: nonce
            }),
            signature
        );
    }

    function _rejectBySig(uint256 jobId, bytes32 reason, uint64 deadline, uint256 nonce) internal {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(UNDERWRITER_PK, _rejectDecisionDigest(jobId, reason, deadline, nonce));
        bytes memory signature = abi.encodePacked(r, s, v);

        evaluator.rejectBySig(
            TwoStageUnderwritingTypes.RejectDecision({
                jobId: jobId,
                reason: reason,
                deadline: deadline,
                nonce: nonce
            }),
            signature
        );
    }

    function _completeRootToAwaitingClose() internal {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit(true);
        _commitJob(ROOT_JOB_ID, commit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        _protect(ROOT_JOB_ID);
        _submitEvidence(ROOT_JOB_ID, commit);
        _completeBySig(ROOT_JOB_ID, bytes32("ok"), uint64(block.timestamp + 1 days), 1);
    }

    function _completeDecisionDigest(uint256 jobId, bytes32 reason, uint64 deadline, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("TwoStage Underwriting Evaluator")),
                keccak256(bytes("1")),
                block.chainid,
                address(evaluator)
            )
        );
        bytes32 structHash = keccak256(abi.encode(COMPLETE_TYPEHASH, jobId, reason, deadline, nonce));

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _rejectDecisionDigest(uint256 jobId, bytes32 reason, uint64 deadline, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("TwoStage Underwriting Evaluator")),
                keccak256(bytes("1")),
                block.chainid,
                address(evaluator)
            )
        );
        bytes32 structHash = keccak256(abi.encode(REJECT_TYPEHASH, jobId, reason, deadline, nonce));

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

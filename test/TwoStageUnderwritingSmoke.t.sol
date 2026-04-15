// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/interfaces/IAgenticCommerce.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingCoordinator.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingEvaluator.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingHook.sol";
import "../contracts/workflows/two-stage-underwriting/TwoStageUnderwritingTypes.sol";
import "./mocks/MockAgenticCommerce.sol";

contract TwoStageUnderwritingSmokeTest is Test {
    uint256 internal constant ROOT_JOB_ID = 1;
    uint256 internal constant CLOSE_JOB_ID = 2;
    uint256 internal constant REPLACEMENT_CLOSE_JOB_ID = 3;
    uint256 internal constant AMOUNT = 1 ether;
    uint256 internal constant UNDERWRITER_PK = 0xA11CE;

    address internal constant CLIENT = address(0xCA11);
    address internal constant PROVIDER = address(0xBEEF);
    address internal constant PAYMENT_TOKEN = address(0xC0FFEE);

    MockAgenticCommerce internal acp;
    TwoStageUnderwritingHook internal hook;
    TwoStageUnderwritingEvaluator internal evaluator;
    TwoStageUnderwritingCoordinator internal coordinator;
    address internal underwriter;
    bytes32 internal constant COMPLETE_TYPEHASH =
        keccak256("CompleteDecision(uint256 jobId,bytes32 reason,uint64 deadline,uint256 nonce)");

    function setUp() public {
        underwriter = vm.addr(UNDERWRITER_PK);
        acp = new MockAgenticCommerce();
        hook = new TwoStageUnderwritingHook(address(acp), address(this));
        evaluator = new TwoStageUnderwritingEvaluator(address(acp), address(hook));
        coordinator = new TwoStageUnderwritingCoordinator(address(acp), address(hook));

        hook.setWiring(address(evaluator), address(coordinator));
        hook.registerUnderwriter(underwriter);

        _setJob(ROOT_JOB_ID, "root", IAgenticCommerce.JobStatus.Open);
    }

    function test_rootWorkflow_advancesThroughProtection() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit();

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

        coordinator.orchestrateFunding(ROOT_JOB_ID);

        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.Protected)
        );
        assertEq(hook.jobSettlementJobId(ROOT_JOB_ID), ROOT_JOB_ID);
    }

    function test_onlyEvaluatorMayRelayCompletionAfterEvidenceSubmission() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit();

        _commitJob(ROOT_JOB_ID, commit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        coordinator.orchestrateFunding(ROOT_JOB_ID);
        _submitEvidence(ROOT_JOB_ID, commit);

        vm.expectRevert(TwoStageUnderwritingHook.OnlyEvaluator.selector);
        acp.complete(ROOT_JOB_ID, bytes32("bad"), "");

        bytes32 reason = bytes32("ok");
        uint64 deadline = uint64(block.timestamp + 1 days);
        uint256 nonce = 1;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(UNDERWRITER_PK, _completeDecisionDigest(ROOT_JOB_ID, reason, deadline, nonce));
        bytes memory signature = abi.encodePacked(r, s, v);

        evaluator.completeBySig(
            TwoStageUnderwritingTypes.CompleteDecision({
                jobId: ROOT_JOB_ID,
                reason: reason,
                deadline: deadline,
                nonce: nonce
            }),
            signature
        );

        assertEq(uint256(acp.getJob(ROOT_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Completed));
        assertTrue(hook.isAwaitingClose(ROOT_JOB_ID));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.AwaitingClose)
        );
    }

    function test_onlyClientMayRejectCommittedOpenJob() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory commit = _rootCommit();
        bytes32 reason = bytes32("nope");

        _commitJob(ROOT_JOB_ID, commit);

        vm.expectRevert(TwoStageUnderwritingHook.OnlyClient.selector);
        acp.reject(ROOT_JOB_ID, reason, "");

        vm.prank(CLIENT);
        acp.reject(ROOT_JOB_ID, reason, "");

        assertEq(uint256(acp.getJob(ROOT_JOB_ID).status), uint256(IAgenticCommerce.JobStatus.Rejected));
        assertEq(
            uint256(hook.jobSidecarState(ROOT_JOB_ID)),
            uint256(TwoStageUnderwritingTypes.SidecarState.RejectSettled)
        );
    }

    function test_cancelledActiveCloseSlot_canBeReplaced() public {
        TwoStageUnderwritingTypes.UnderwriteCommit memory rootCommit = _rootCommit();

        _commitJob(ROOT_JOB_ID, rootCommit);
        _fundToFeeEscrowed(ROOT_JOB_ID);
        coordinator.orchestrateFunding(ROOT_JOB_ID);
        _submitEvidence(ROOT_JOB_ID, rootCommit);
        _completeRootBySig();

        _setJob(CLOSE_JOB_ID, "close", IAgenticCommerce.JobStatus.Open);
        _setJob(REPLACEMENT_CLOSE_JOB_ID, "replacement-close", IAgenticCommerce.JobStatus.Open);

        TwoStageUnderwritingTypes.UnderwriteCommit memory closeCommit = TwoStageUnderwritingTypes.UnderwriteCommit({
            parentJobId: ROOT_JOB_ID,
            underwriter: underwriter,
            validUntil: uint64(block.timestamp + 1 days),
            policyHash: keccak256("policy"),
            quoteIdHash: keccak256("quote"),
            termsHash: keccak256("close-terms"),
            allowCloseJob: false
        });

        _commitJob(CLOSE_JOB_ID, closeCommit);
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), CLOSE_JOB_ID);

        acp.setJobStatus(CLOSE_JOB_ID, IAgenticCommerce.JobStatus.Cancelled);

        _commitJob(REPLACEMENT_CLOSE_JOB_ID, closeCommit);
        assertEq(hook.getActiveCloseJobId(ROOT_JOB_ID), REPLACEMENT_CLOSE_JOB_ID);
        assertEq(hook.getParentJobId(REPLACEMENT_CLOSE_JOB_ID), ROOT_JOB_ID);
    }

    function _rootCommit() internal view returns (TwoStageUnderwritingTypes.UnderwriteCommit memory) {
        return TwoStageUnderwritingTypes.UnderwriteCommit({
            parentJobId: 0,
            underwriter: underwriter,
            validUntil: uint64(block.timestamp + 1 days),
            policyHash: keccak256("policy"),
            quoteIdHash: keccak256("quote"),
            termsHash: keccak256("terms"),
            allowCloseJob: true
        });
    }

    function _setJob(uint256 jobId, string memory description, IAgenticCommerce.JobStatus status) internal {
        acp.setJob(
            IAgenticCommerce.Job({
                id: jobId,
                client: CLIENT,
                provider: PROVIDER,
                evaluator: address(evaluator),
                description: description,
                budget: 0,
                expiredAt: block.timestamp + 1 days,
                status: status,
                hook: address(hook),
                paymentToken: PAYMENT_TOKEN,
                providerAgentId: 0
            })
        );
    }

    function _commitJob(uint256 jobId, TwoStageUnderwritingTypes.UnderwriteCommit memory commit) internal {
        bytes4 setBudgetSelector = bytes4(keccak256("setBudget(uint256,address,uint256,bytes)"));
        bytes memory setBudgetData = abi.encode(CLIENT, PAYMENT_TOKEN, AMOUNT, abi.encode(commit));

        acp.callBeforeAction(hook, jobId, setBudgetSelector, setBudgetData);
        acp.callAfterAction(hook, jobId, setBudgetSelector, setBudgetData);
    }

    function _fundToFeeEscrowed(uint256 jobId) internal {
        bytes4 fundSelector = bytes4(keccak256("fund(uint256,uint256,bytes)"));
        bytes memory fundData = abi.encode(CLIENT, bytes(""));

        acp.callBeforeAction(hook, jobId, fundSelector, fundData);
        acp.setJobStatus(jobId, IAgenticCommerce.JobStatus.Funded);
        acp.callAfterAction(hook, jobId, fundSelector, fundData);
    }

    function _submitEvidence(uint256 jobId, TwoStageUnderwritingTypes.UnderwriteCommit memory commit) internal {
        bytes4 submitSelector = bytes4(keccak256("submit(uint256,bytes32,bytes)"));
        TwoStageUnderwritingTypes.SubmitEvidence memory evidence = TwoStageUnderwritingTypes.SubmitEvidence({
            bundleHash: keccak256("bundle"),
            policyHash: commit.policyHash,
            quoteIdHash: commit.quoteIdHash,
            termsHash: commit.termsHash
        });
        bytes memory submitData = abi.encode(PROVIDER, evidence.bundleHash, abi.encode(evidence));

        acp.callBeforeAction(hook, jobId, submitSelector, submitData);
        acp.setJobStatus(jobId, IAgenticCommerce.JobStatus.Submitted);
        acp.callAfterAction(hook, jobId, submitSelector, submitData);
    }

    function _completeRootBySig() internal {
        bytes32 reason = bytes32("ok");
        uint64 deadline = uint64(block.timestamp + 1 days);
        uint256 nonce = 7;
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(UNDERWRITER_PK, _completeDecisionDigest(ROOT_JOB_ID, reason, deadline, nonce));
        bytes memory signature = abi.encodePacked(r, s, v);

        evaluator.completeBySig(
            TwoStageUnderwritingTypes.CompleteDecision({
                jobId: ROOT_JOB_ID,
                reason: reason,
                deadline: deadline,
                nonce: nonce
            }),
            signature
        );
    }

    function _completeDecisionDigest(uint256 jobId, bytes32 reason, uint64 deadline, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainTypehash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(
            abi.encode(
                domainTypehash,
                keccak256(bytes("TwoStage Underwriting Evaluator")),
                keccak256(bytes("1")),
                block.chainid,
                address(evaluator)
            )
        );
        bytes32 structHash = keccak256(abi.encode(COMPLETE_TYPEHASH, jobId, reason, deadline, nonce));

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

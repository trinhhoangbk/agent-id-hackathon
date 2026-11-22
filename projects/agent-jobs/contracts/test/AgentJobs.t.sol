// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentJobs} from "../src/AgentJobs.sol";
import {AgentReputation} from "../src/AgentReputation.sol";
import {MockAgentID} from "../src/MockAgentID.sol";

contract AgentJobsTest is Test {
    MockAgentID id;
    AgentJobs jobs;
    AgentReputation rep;
    address client = makeAddr("client");
    address agent = makeAddr("agent");
    address other = makeAddr("other");
    address nobody = makeAddr("nobody"); // no Agent ID

    function setUp() public {
        id = new MockAgentID();
        jobs = new AgentJobs(id);
        rep = jobs.reputation();
        _claim(client, "alice");
        _claim(agent, "bot");
        _claim(other, "carol");
        vm.deal(client, 10 ether);
        vm.deal(nobody, 10 ether);
    }

    function _claim(address who, string memory h) internal {
        vm.prank(who);
        id.claim(h);
    }

    function _create(string memory assignee) internal returns (uint256) {
        vm.prank(client);
        return jobs.createJob{value: 1 ether}("summarize", uint40(block.timestamp + 1 days), assignee, "research");
    }

    function _takeSubmit(uint256 j) internal {
        vm.prank(agent);
        jobs.takeJob(j);
        vm.prank(agent);
        jobs.submit(j, "ipfs://result");
    }

    function test_happyPath_paysAndRates() public {
        uint256 j = _create("");
        _takeSubmit(j);
        vm.prank(client);
        jobs.approve(j, 5);
        assertEq(agent.balance, 1 ether);
        assertEq(address(jobs).balance, 0);
        (uint32 done, uint32 cnt, uint32 sum,, uint128 earned) = rep.reps(agent);
        assertEq(done, 1);
        assertEq(cnt, 1);
        assertEq(sum, 5);
        assertEq(earned, 1 ether);
        assertEq(rep.agentsCount(), 1);
    }

    function test_cannotApproveTwice() public {
        uint256 j = _create("");
        _takeSubmit(j);
        vm.prank(client);
        jobs.approve(j, 4);
        vm.prank(client);
        vm.expectRevert(AgentJobs.BadStatus.selector);
        jobs.approve(j, 4);
    }

    function test_requiresAgentID() public {
        vm.prank(nobody);
        vm.expectRevert(AgentJobs.NoAgentID.selector);
        jobs.createJob{value: 1 ether}("x", uint40(block.timestamp + 1), "", "research");
        uint256 j = _create("");
        vm.prank(nobody);
        vm.expectRevert(AgentJobs.NoAgentID.selector);
        jobs.takeJob(j);
    }

    function test_assignedByHandle() public {
        uint256 j = _create("bot");
        assertEq(jobs.getJob(j).agent, agent);
        vm.prank(other);
        vm.expectRevert(AgentJobs.NotAssignee.selector);
        jobs.takeJob(j);
        vm.prank(agent);
        jobs.takeJob(j);
    }

    function test_unknownHandleReverts() public {
        vm.prank(client);
        vm.expectRevert(AgentJobs.UnknownHandle.selector);
        jobs.createJob{value: 1 ether}("x", uint40(block.timestamp + 1), "ghost", "research");
    }

    function test_clientCannotTakeOwnJob() public {
        uint256 j = _create("");
        vm.prank(client);
        vm.expectRevert(AgentJobs.NotAssignee.selector);
        jobs.takeJob(j);
    }

    function test_refundOpen() public {
        uint256 j = _create("");
        vm.prank(client);
        jobs.refund(j);
        assertEq(client.balance, 10 ether);
    }

    function test_refundTakenOnlyAfterDeadline() public {
        uint256 j = _create("");
        vm.prank(agent);
        jobs.takeJob(j);
        vm.prank(client);
        vm.expectRevert(AgentJobs.TooEarly.selector);
        jobs.refund(j);
        vm.warp(block.timestamp + 1 days);
        vm.prank(agent);
        vm.expectRevert(AgentJobs.TooLate.selector);
        jobs.submit(j, "late");
        vm.prank(client);
        jobs.refund(j);
        assertEq(client.balance, 10 ether);
    }

    function test_cannotRefundSubmitted() public {
        uint256 j = _create("");
        _takeSubmit(j);
        vm.warp(block.timestamp + 30 days);
        vm.prank(client);
        vm.expectRevert(AgentJobs.BadStatus.selector);
        jobs.refund(j);
    }

    function test_releaseAfterReviewPeriod() public {
        uint256 j = _create("");
        _takeSubmit(j);
        vm.prank(agent);
        vm.expectRevert(AgentJobs.TooEarly.selector);
        jobs.release(j);
        vm.warp(block.timestamp + 3 days);
        vm.prank(agent);
        jobs.release(j);
        assertEq(agent.balance, 1 ether);
        (uint32 done, uint32 cnt,,,) = rep.reps(agent);
        assertEq(done, 1);
        assertEq(cnt, 0);
    }

    function test_releaseBeforeSubmitReverts() public {
        uint256 j = _create("");
        vm.prank(agent);
        jobs.takeJob(j);
        vm.prank(agent);
        vm.expectRevert(AgentJobs.BadStatus.selector);
        jobs.release(j);
    }

    function test_badRating() public {
        uint256 j = _create("");
        _takeSubmit(j);
        vm.startPrank(client);
        vm.expectRevert(AgentJobs.BadRating.selector);
        jobs.approve(j, 0);
        vm.expectRevert(AgentJobs.BadRating.selector);
        jobs.approve(j, 6);
        vm.stopPrank();
    }

    function test_onlyJobsCanRecord() public {
        vm.expectRevert(AgentReputation.NotJobs.selector);
        rep.record(agent, client, 0, 5, 1);
    }

    function test_endorseOncePerPair() public {
        vm.prank(client);
        rep.endorse(agent);
        (,,, uint32 e,) = rep.reps(agent);
        assertEq(e, 1);
        vm.prank(client);
        vm.expectRevert(AgentReputation.AlreadyEndorsed.selector);
        rep.endorse(agent);
        vm.prank(agent);
        vm.expectRevert(AgentReputation.SelfEndorse.selector);
        rep.endorse(agent);
        vm.prank(nobody);
        vm.expectRevert(AgentReputation.NoAgentID.selector);
        rep.endorse(agent);
    }

    function test_tagStoredAndBounded() public {
        uint256 j = _create("");
        assertEq(jobs.getJob(j).tag, "research");
        vm.prank(client);
        vm.expectRevert(AgentJobs.TagTooLong.selector);
        jobs.createJob{value: 1 ether}("x", uint40(block.timestamp + 1), "", "this-tag-is-way-too-long-for-the-limit");
    }

    // ---- linking a normal wallet to an Agent ID (the Agentic Wallet can't connect to dApps) ----

    address hot = makeAddr("hot"); // e.g. the user's normal Binance Wallet account, no Agent ID

    function _link(address controller, address idWallet, string memory h) internal {
        vm.prank(controller);
        jobs.requestLink(h);
        vm.deal(idWallet, idWallet.balance + 0.001 ether);
        uint256 before = idWallet.balance;
        vm.prank(idWallet);
        (bool ok,) = address(jobs).call{value: 0.001 ether}("");
        assertTrue(ok);
        assertEq(idWallet.balance, before, "confirming transfer is refunded");
    }

    function test_linkedWalletActsForAgentID() public {
        _link(hot, agent, "bot");
        assertEq(jobs.identityOf(hot), agent);
        assertEq(jobs.controllerOf(agent), hot);
        uint256 j = _create("bot"); // assigned to bot.ai
        vm.prank(hot);
        jobs.takeJob(j);
        vm.prank(hot);
        jobs.submit(j, "done");
        assertEq(jobs.getJob(j).agent, agent, "job is credited to the Agent ID, not the hot wallet");
        uint256 before = agent.balance;
        vm.prank(client);
        jobs.approve(j, 4);
        assertEq(agent.balance - before, 1 ether, "earnings go to the name.ai wallet");
        (uint32 done,,,,) = rep.reps(agent);
        assertEq(done, 1);
    }

    function test_linkedWalletPostsAndRefunds() public {
        _link(nobody, client, "alice");
        vm.prank(nobody);
        uint256 j = jobs.createJob{value: 1 ether}("x", uint40(block.timestamp + 1 days), "", "");
        assertEq(jobs.getJob(j).client, client);
        uint256 before = nobody.balance;
        vm.prank(nobody);
        jobs.refund(j);
        assertEq(nobody.balance, before + 1 ether);
    }

    function test_linkedWalletEndorses() public {
        _link(hot, agent, "bot");
        vm.prank(hot);
        rep.endorse(other);
        assertTrue(rep.endorsed(agent, other));
        vm.prank(hot);
        vm.expectRevert(AgentReputation.SelfEndorse.selector);
        rep.endorse(agent);
    }

    function test_linkNeedsConfirmFromIdWallet() public {
        vm.prank(hot);
        jobs.requestLink("bot");
        assertEq(jobs.identityOf(hot), address(0), "request alone grants nothing");
        vm.deal(other, 1 ether);
        vm.prank(other); // a different Agent ID wallet can't confirm bot's request
        (bool ok,) = address(jobs).call{value: 1}("");
        assertFalse(ok);
        vm.warp(block.timestamp + 1 hours);
        vm.deal(agent, 1 ether);
        vm.prank(agent); // expired
        (ok,) = address(jobs).call{value: 1}("");
        assertFalse(ok);
    }

    function test_pendingLinkCannotBeHijacked() public {
        vm.prank(hot);
        jobs.requestLink("bot");
        vm.prank(nobody);
        vm.expectRevert(AgentJobs.LinkPending.selector);
        jobs.requestLink("bot");
        vm.warp(block.timestamp + 1 hours); // after expiry anyone may request again
        vm.prank(nobody);
        jobs.requestLink("bot");
    }

    function test_relinkAndUnlink() public {
        _link(hot, agent, "bot");
        _link(nobody, agent, "bot"); // new wallet replaces the old one
        assertEq(jobs.identityOf(hot), address(0));
        assertEq(jobs.identityOf(nobody), agent);
        vm.prank(nobody);
        jobs.unlink();
        assertEq(jobs.identityOf(nobody), address(0));
        assertEq(jobs.controllerOf(agent), address(0));
    }
}

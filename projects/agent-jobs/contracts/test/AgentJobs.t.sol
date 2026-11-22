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
        return jobs.createJob{value: 1 ether}("summarize", uint40(block.timestamp + 1 days), assignee);
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
        jobs.createJob{value: 1 ether}("x", uint40(block.timestamp + 1), "");
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
        jobs.createJob{value: 1 ether}("x", uint40(block.timestamp + 1), "ghost");
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
}

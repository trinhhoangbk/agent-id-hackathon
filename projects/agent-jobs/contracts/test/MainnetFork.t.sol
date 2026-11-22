// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentJobs} from "../src/AgentJobs.sol";
import {IAgentID} from "../src/IAgentID.sol";

/// Runs against the real Agent ID registry: forge test --match-contract MainnetFork --fork-url bsc
contract MainnetForkTest is Test {
    IAgentID constant REG = IAgentID(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    address constant HOLDER = 0x49f12e1Ca7941998d6B7Bc97B0765FC910aBb352; // wyc1981.ai

    function test_realRegistry() public {
        if (block.chainid != 56) return; // only meaningful on a BSC fork
        AgentJobs jobs = new AgentJobs(REG);
        assertEq(REG.handleOf(HOLDER), "wyc1981");
        address client = makeAddr("noIdClient");
        vm.deal(client, 1 ether);
        vm.prank(client);
        vm.expectRevert(AgentJobs.NoAgentID.selector);
        jobs.createJob{value: 0.1 ether}("x", uint40(block.timestamp + 1 days), "");

        vm.deal(HOLDER, 1 ether);
        vm.prank(HOLDER);
        jobs.createJob{value: 0.1 ether}("x", uint40(block.timestamp + 1 days), "");
        assertEq(jobs.getJob(0).client, HOLDER);
    }
}

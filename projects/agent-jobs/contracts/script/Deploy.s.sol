// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentJobs} from "../src/AgentJobs.sol";
import {IAgentID} from "../src/IAgentID.sol";
import {MockAgentID} from "../src/MockAgentID.sol";

/// Mainnet (56): uses the real Agent ID registry. Any other chain: deploys MockAgentID first.
contract Deploy is Script {
    address constant AGENT_ID_MAINNET = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external {
        vm.startBroadcast();
        address registry = block.chainid == 56 ? AGENT_ID_MAINNET : address(new MockAgentID());
        AgentJobs jobs = new AgentJobs(IAgentID(registry));
        vm.stopBroadcast();
        console.log("AgentID     ", registry);
        console.log("AgentJobs   ", address(jobs));
        console.log("Reputation  ", address(jobs.reputation()));
    }
}

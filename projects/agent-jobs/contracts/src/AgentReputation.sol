// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentID} from "./IAgentID.sol";

interface IIdentity {
    function identityOf(address) external view returns (address);
}

/// Non-transferable reputation keyed by Agent ID holder. Because Agent IDs are
/// soulbound and one-per-user, this score cannot be bought or farmed with fresh wallets.
/// Job stats are written only by AgentJobs (its deployer); endorsements by any holder.
contract AgentReputation {
    struct Rep {
        uint32 jobsDone;
        uint32 ratingCount;
        uint32 ratingSum;
        uint32 endorsements;
        uint128 earned; // wei
    }

    IAgentID public immutable agentId;
    address public immutable jobs;

    mapping(address => Rep) public reps;
    mapping(address => mapping(address => bool)) public endorsed; // from => to
    address[] public agents;
    mapping(address => bool) private known;

    event JobRecorded(address indexed agent, address indexed client, uint256 indexed jobId, uint8 rating, uint256 amount);
    event Endorsed(address indexed from, address indexed to);

    error NotJobs();
    error NoAgentID();
    error BadRating();
    error SelfEndorse();
    error AlreadyEndorsed();

    constructor(IAgentID _agentId) {
        agentId = _agentId;
        jobs = msg.sender;
    }

    /// rating 0 = completed without a rating (auto-release after review timeout).
    function record(address agent, address client, uint256 jobId, uint8 rating, uint256 amount) external {
        if (msg.sender != jobs) revert NotJobs();
        if (rating > 5) revert BadRating();
        Rep storage r = reps[agent];
        r.jobsDone++;
        r.earned += uint128(amount);
        if (rating > 0) {
            r.ratingCount++;
            r.ratingSum += rating;
        }
        _track(agent);
        emit JobRecorded(agent, client, jobId, rating, amount);
    }

    /// Callable from an Agent ID wallet or a wallet linked to one in AgentJobs.
    function endorse(address to) external {
        address from = IIdentity(jobs).identityOf(msg.sender);
        if (from == address(0) || agentId.balanceOf(to) == 0) revert NoAgentID();
        if (to == from) revert SelfEndorse();
        if (endorsed[from][to]) revert AlreadyEndorsed();
        endorsed[from][to] = true;
        reps[to].endorsements++;
        _track(to);
        emit Endorsed(from, to);
    }

    function agentsCount() external view returns (uint256) {
        return agents.length;
    }

    function reputationOfHandle(string calldata handle) external view returns (address owner, Rep memory rep) {
        owner = agentId.ownerOfHandle(handle);
        rep = reps[owner];
    }

    function _track(address a) private {
        if (!known[a]) {
            known[a] = true;
            agents.push(a);
        }
    }
}

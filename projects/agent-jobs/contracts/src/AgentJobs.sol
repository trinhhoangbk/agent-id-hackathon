// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentID} from "./IAgentID.sol";
import {AgentReputation} from "./AgentReputation.sol";

/// Escrowed job board for AI agents identified by Agent ID (name.ai).
/// Open -> Taken -> Submitted -> Paid, or Open/expired-Taken -> Refunded.
/// shortcut: native BNB only and no third-party dispute arbitration; add ERC-20 + arbiter if needed.
contract AgentJobs {
    enum Status {
        Open,
        Taken,
        Submitted,
        Paid,
        Refunded
    }

    struct Job {
        address client;
        address agent; // assigned agent (preset via handle) or taker
        uint96 reward;
        uint40 deadline; // agent must submit before this
        uint40 submittedAt;
        Status status;
        string spec;
        string result;
        string tag; // category, lowercase; set by client or auto-suggested by the UI
    }

    /// After submission the client has this long to approve; then the agent can self-release.
    uint256 public constant REVIEW_PERIOD = 3 days;

    IAgentID public immutable agentId;
    AgentReputation public immutable reputation;
    Job[] internal _jobs;

    event JobCreated(uint256 indexed id, address indexed client, address indexed assignee, uint256 reward, uint40 deadline);
    event JobTaken(uint256 indexed id, address indexed agent);
    event JobSubmitted(uint256 indexed id, address indexed agent);
    event JobPaid(uint256 indexed id, address indexed agent, uint256 reward, uint8 rating);
    event JobRefunded(uint256 indexed id, address indexed client, uint256 reward);

    error NoAgentID();
    error UnknownHandle();
    error BadStatus();
    error NotClient();
    error NotAgent();
    error NotAssignee();
    error BadDeadline();
    error ZeroReward();
    error TooEarly();
    error TooLate();
    error BadRating();
    error TransferFailed();
    error TagTooLong();

    constructor(IAgentID _agentId) {
        agentId = _agentId;
        reputation = new AgentReputation(_agentId);
    }

    modifier onlyHolder() {
        if (agentId.balanceOf(msg.sender) == 0) revert NoAgentID();
        _;
    }

    /// @param assignee Agent ID handle without ".ai" to hire directly, or "" for an open job.
    /// @param tag Short category label (max 32 bytes), e.g. "research".
    function createJob(string calldata spec, uint40 deadline, string calldata assignee, string calldata tag)
        external
        payable
        onlyHolder
        returns (uint256 id)
    {
        if (msg.value == 0) revert ZeroReward();
        if (deadline <= block.timestamp) revert BadDeadline();
        if (bytes(tag).length > 32) revert TagTooLong();
        address agent;
        if (bytes(assignee).length != 0) {
            agent = agentId.ownerOfHandle(assignee);
            if (agent == address(0)) revert UnknownHandle();
            if (agent == msg.sender) revert NotAssignee();
        }
        id = _jobs.length;
        _jobs.push(Job(msg.sender, agent, uint96(msg.value), deadline, 0, Status.Open, spec, "", tag));
        emit JobCreated(id, msg.sender, agent, msg.value, deadline);
    }

    function takeJob(uint256 id) external onlyHolder {
        Job storage j = _jobs[id];
        if (j.status != Status.Open) revert BadStatus();
        if (block.timestamp >= j.deadline) revert TooLate();
        if (msg.sender == j.client) revert NotAssignee();
        if (j.agent != address(0) && j.agent != msg.sender) revert NotAssignee();
        j.agent = msg.sender;
        j.status = Status.Taken;
        emit JobTaken(id, msg.sender);
    }

    function submit(uint256 id, string calldata result) external {
        Job storage j = _jobs[id];
        if (j.status != Status.Taken) revert BadStatus();
        if (msg.sender != j.agent) revert NotAgent();
        if (block.timestamp >= j.deadline) revert TooLate();
        j.result = result;
        j.submittedAt = uint40(block.timestamp);
        j.status = Status.Submitted;
        emit JobSubmitted(id, msg.sender);
    }

    /// @param rating 1..5
    function approve(uint256 id, uint8 rating) external {
        Job storage j = _jobs[id];
        if (msg.sender != j.client) revert NotClient();
        if (rating == 0 || rating > 5) revert BadRating();
        _pay(id, j, rating);
    }

    /// Agent self-releases if the client ignored the submission past REVIEW_PERIOD (no rating recorded).
    function release(uint256 id) external {
        Job storage j = _jobs[id];
        if (msg.sender != j.agent) revert NotAgent();
        if (j.status == Status.Submitted && block.timestamp < j.submittedAt + REVIEW_PERIOD) revert TooEarly();
        _pay(id, j, 0);
    }

    /// Client refunds an open job anytime, or a taken job the agent failed to deliver by the deadline.
    function refund(uint256 id) external {
        Job storage j = _jobs[id];
        if (msg.sender != j.client) revert NotClient();
        if (j.status == Status.Taken) {
            if (block.timestamp < j.deadline) revert TooEarly();
        } else if (j.status != Status.Open) {
            revert BadStatus();
        }
        j.status = Status.Refunded;
        uint256 amount = j.reward;
        emit JobRefunded(id, msg.sender, amount);
        _send(msg.sender, amount);
    }

    function _pay(uint256 id, Job storage j, uint8 rating) private {
        if (j.status != Status.Submitted) revert BadStatus();
        j.status = Status.Paid;
        uint256 amount = j.reward;
        reputation.record(j.agent, j.client, id, rating, amount);
        emit JobPaid(id, j.agent, amount, rating);
        _send(j.agent, amount);
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function jobsCount() external view returns (uint256) {
        return _jobs.length;
    }

    function getJob(uint256 id) external view returns (Job memory) {
        return _jobs[id];
    }
}

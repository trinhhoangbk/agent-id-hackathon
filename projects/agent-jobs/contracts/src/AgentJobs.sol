// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentID} from "./IAgentID.sol";
import {AgentReputation} from "./AgentReputation.sol";

/// Escrowed job board for AI agents identified by Agent ID (name.ai).
/// Open -> Taken -> Submitted -> Paid, or Open/expired-Taken -> Refunded.
/// The Agentic Wallet that holds an Agent ID cannot connect to web dApps, so any wallet can be linked to act
/// for a name.ai: the wallet calls requestLink(handle), then the Agent ID wallet sends any BNB here (refunded).
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

    /// How long a link request waits for the Agent ID wallet's confirming transfer.
    uint256 public constant LINK_WINDOW = 1 hours;

    struct PendingLink {
        address controller;
        uint40 expires;
    }

    mapping(address idWallet => PendingLink) public pendingLink;
    mapping(address controller => address idWallet) public linkedId;
    mapping(address idWallet => address controller) public controllerOf;

    event JobCreated(uint256 indexed id, address indexed client, address indexed assignee, uint256 reward, uint40 deadline);
    event JobTaken(uint256 indexed id, address indexed agent);
    event JobSubmitted(uint256 indexed id, address indexed agent);
    event JobPaid(uint256 indexed id, address indexed agent, uint256 reward, uint8 rating);
    event JobRefunded(uint256 indexed id, address indexed client, uint256 reward);
    event LinkRequested(address indexed idWallet, address indexed controller);
    event Linked(address indexed idWallet, address indexed controller);
    event Unlinked(address indexed idWallet, address indexed controller);

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
    error LinkPending();
    error NoLink();

    constructor(IAgentID _agentId) {
        agentId = _agentId;
        reputation = new AgentReputation(_agentId);
    }

    /// The Agent ID wallet an address acts as: its own, or the one it is linked to. 0 if none.
    function identityOf(address a) public view returns (address) {
        if (agentId.balanceOf(a) > 0) return a;
        address id = linkedId[a];
        return id != address(0) && agentId.balanceOf(id) > 0 ? id : address(0);
    }

    function _me() private view returns (address id) {
        id = identityOf(msg.sender);
        if (id == address(0)) revert NoAgentID();
    }

    /// Step 1, from the wallet that will act: ask to act for handle.ai.
    /// shortcut: a pending request blocks others for LINK_WINDOW, so a stranger can delay (not steal) a link;
    /// the UI shows whose request is pending before the owner confirms.
    function requestLink(string calldata handle) external {
        address id = agentId.ownerOfHandle(handle);
        if (id == address(0)) revert UnknownHandle();
        PendingLink storage p = pendingLink[id];
        if (p.controller != msg.sender && p.expires > block.timestamp) revert LinkPending();
        pendingLink[id] = PendingLink(msg.sender, uint40(block.timestamp + LINK_WINDOW));
        emit LinkRequested(id, msg.sender);
    }

    /// Step 2, from the Agent ID wallet: send any BNB to this contract; it is refunded in the same transaction.
    receive() external payable {
        PendingLink memory p = pendingLink[msg.sender];
        if (p.controller == address(0) || p.expires <= block.timestamp) revert NoLink();
        delete pendingLink[msg.sender];
        address oldController = controllerOf[msg.sender];
        if (oldController != address(0)) delete linkedId[oldController];
        address oldId = linkedId[p.controller]; // a wallet acts for one Agent ID at a time
        if (oldId != address(0)) delete controllerOf[oldId];
        linkedId[p.controller] = msg.sender;
        controllerOf[msg.sender] = p.controller;
        emit Linked(msg.sender, p.controller);
        _send(msg.sender, msg.value);
    }

    function unlink() external {
        address id = linkedId[msg.sender];
        if (id == address(0)) revert NoLink();
        delete linkedId[msg.sender];
        delete controllerOf[id];
        emit Unlinked(id, msg.sender);
    }

    /// @param assignee Agent ID handle without ".ai" to hire directly, or "" for an open job.
    /// @param tag Short category label (max 32 bytes), e.g. "research".
    function createJob(string calldata spec, uint40 deadline, string calldata assignee, string calldata tag)
        external
        payable
        returns (uint256 id)
    {
        address me = _me();
        if (msg.value == 0) revert ZeroReward();
        if (deadline <= block.timestamp) revert BadDeadline();
        if (bytes(tag).length > 32) revert TagTooLong();
        address agent;
        if (bytes(assignee).length != 0) {
            agent = agentId.ownerOfHandle(assignee);
            if (agent == address(0)) revert UnknownHandle();
            if (agent == me) revert NotAssignee();
        }
        id = _jobs.length;
        _jobs.push(Job(me, agent, uint96(msg.value), deadline, 0, Status.Open, spec, "", tag));
        emit JobCreated(id, me, agent, msg.value, deadline);
    }

    function takeJob(uint256 id) external {
        address me = _me();
        Job storage j = _jobs[id];
        if (j.status != Status.Open) revert BadStatus();
        if (block.timestamp >= j.deadline) revert TooLate();
        if (me == j.client) revert NotAssignee();
        if (j.agent != address(0) && j.agent != me) revert NotAssignee();
        j.agent = me;
        j.status = Status.Taken;
        emit JobTaken(id, me);
    }

    function submit(uint256 id, string calldata result) external {
        Job storage j = _jobs[id];
        if (j.status != Status.Taken) revert BadStatus();
        if (identityOf(msg.sender) != j.agent) revert NotAgent();
        if (block.timestamp >= j.deadline) revert TooLate();
        j.result = result;
        j.submittedAt = uint40(block.timestamp);
        j.status = Status.Submitted;
        emit JobSubmitted(id, j.agent);
    }

    /// @param rating 1..5
    function approve(uint256 id, uint8 rating) external {
        Job storage j = _jobs[id];
        if (identityOf(msg.sender) != j.client) revert NotClient();
        if (rating == 0 || rating > 5) revert BadRating();
        _pay(id, j, rating);
    }

    /// Agent self-releases if the client ignored the submission past REVIEW_PERIOD (no rating recorded).
    function release(uint256 id) external {
        Job storage j = _jobs[id];
        if (identityOf(msg.sender) != j.agent) revert NotAgent();
        if (j.status == Status.Submitted && block.timestamp < j.submittedAt + REVIEW_PERIOD) revert TooEarly();
        _pay(id, j, 0);
    }

    /// Client refunds an open job anytime, or a taken job the agent failed to deliver by the deadline.
    function refund(uint256 id) external {
        Job storage j = _jobs[id];
        if (identityOf(msg.sender) != j.client) revert NotClient();
        if (j.status == Status.Taken) {
            if (block.timestamp < j.deadline) revert TooEarly();
        } else if (j.status != Status.Open) {
            revert BadStatus();
        }
        j.status = Status.Refunded;
        uint256 amount = j.reward;
        emit JobRefunded(id, j.client, amount);
        _send(msg.sender, amount); // back to the wallet acting now (the poster's own or linked wallet)
    }

    function _pay(uint256 id, Job storage j, uint8 rating) private {
        if (j.status != Status.Submitted) revert BadStatus();
        j.status = Status.Paid;
        uint256 amount = j.reward;
        reputation.record(j.agent, j.client, id, rating, amount);
        emit JobPaid(id, j.agent, amount, rating);
        _send(j.agent, amount); // earnings go to the name.ai wallet itself
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

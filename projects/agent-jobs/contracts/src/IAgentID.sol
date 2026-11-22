// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Subset of the SPACE ID "Agent ID" (.ai) soulbound registry on BNB Chain
/// mainnet: 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
    /// Handle without the ".ai" suffix, "" if none.
    function handleOf(address owner) external view returns (string memory);
    function ownerOfHandle(string calldata handle) external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentID} from "./IAgentID.sol";

/// Testnet stand-in for the mainnet Agent ID registry: anyone can claim one handle.
contract MockAgentID is IAgentID {
    mapping(address => string) private _handle;
    mapping(string => address) private _owner;

    error HandleTaken();
    error AlreadyHasHandle();
    error EmptyHandle();

    function claim(string calldata handle) external {
        if (bytes(handle).length == 0) revert EmptyHandle();
        if (_owner[handle] != address(0)) revert HandleTaken();
        if (bytes(_handle[msg.sender]).length != 0) revert AlreadyHasHandle();
        _owner[handle] = msg.sender;
        _handle[msg.sender] = handle;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return bytes(_handle[owner]).length == 0 ? 0 : 1;
    }

    function handleOf(address owner) external view returns (string memory) {
        return _handle[owner];
    }

    function ownerOfHandle(string calldata handle) external view returns (address) {
        return _owner[handle];
    }
}

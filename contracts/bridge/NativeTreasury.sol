// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../interfaces/IBridgeLZ.sol";
import "../interfaces/INativeTreasury.sol";


contract NativeTreasury is INativeTreasury, AccessControlEnumerable  {

    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    event ValueSent(uint256 value, address to);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    function callFromTreasury(
        uint256 value_,
        bytes memory data,
        address toSend,
        uint64 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) external onlyRole(BRIDGE_ROLE) {
        IBridgeLZ(msg.sender).sendFromTreasury{value: value_}(data, toSend, chainIdTo, toCall, valueToSpend, comissionLZ);
    }

    function getValue(uint256 value_) external onlyRole(BRIDGE_ROLE) {
        payable(msg.sender).transfer(value_);
        emit ValueSent(value_, msg.sender);
    }

    function withdrawValue(uint256 value_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(value_);
        emit ValueSent(value_, msg.sender);
    }

    receive() external payable {

    }
}
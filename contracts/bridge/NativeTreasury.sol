// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../interfaces/IBridgeLZ.sol";
import "../interfaces/INativeTreasury.sol";


contract NativeTreasury is INativeTreasury, AccessControlEnumerable  {
    
    /// @dev bridge role id
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    event ValueSent(uint256 value, address to);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @dev Make call with value to msg.sender, for LZ bridge
     * 
     * @param value_ value to call
     * @param data  data, which will be sent
     * @param chainIdTo  destination chain id 
     * @param spentValue value which will be spent for axelar delivery
     * @param commission gas and eth value for destination execution
     */
    function callFromTreasury(
        uint256 value_,
        bytes memory data,
        uint64 chainIdTo,
        uint256[][] memory spentValue,
        bytes[] memory commission
    ) external onlyRole(BRIDGE_ROLE) {
        IBridgeLZ(msg.sender).sendFromTreasury{value: value_}(data, chainIdTo, spentValue, commission);
    }

    /**
     * @dev Get value for msg.sender
     * 
     * @param value_ value to transfer
     */
    function getValue(uint256 value_) external onlyRole(BRIDGE_ROLE) {
        payable(msg.sender).transfer(value_);
        emit ValueSent(value_, msg.sender);
    }

    /**
     * @dev Withdraw value 
     * 
     * @param value_ value to withdraw
     */
    function withdrawValue(uint256 value_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(value_);
        emit ValueSent(value_, msg.sender);
    }

    receive() external payable {

    }
}
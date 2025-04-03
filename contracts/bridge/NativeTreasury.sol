// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/INativeTreasury.sol";
import "../interfaces/IGateKeeper.sol";

contract NativeTreasury is INativeTreasury, Ownable {
    address public gateKeeper;
    event ValueSent(uint256 value, address to);

    constructor(address admin_) {
        require(admin_ != address(0), "NativeTreasury: zero address");
        _transferOwnership(admin_);
        gateKeeper = msg.sender;
    }

    receive() external payable {}

    /**
     * @dev Get value for msg.sender
     *
     * @param value_ value to transfer
     */
    function getValue(uint256 value_) external {
        require(msg.sender == gateKeeper || msg.sender == owner(), "NativeTreasury: only admin or gatekeeper");
        payable(msg.sender).transfer(value_);
        emit ValueSent(value_, msg.sender);
    }
}
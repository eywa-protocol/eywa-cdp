// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import "../interfaces/INativeTreasury.sol";
import "../interfaces/IGateKeeper.sol";

contract NativeTreasury is INativeTreasury, AccessControlEnumerable, Initializable  {
    
    /// @dev bridge role id
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    address public gateKeeper;
    event ValueSent(uint256 value, address to);

    constructor() {
        _disableInitializers();
    }
    
    function initialize(address admin_, address gateKeeper_) public initializer {
        require(admin_ != address(0), "NativeTreasury: zero address");
        require(gateKeeper_ != address(0), "NativeTreasury: zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        gateKeeper = gateKeeper_;
    }

    /**
     * @dev Get value for msg.sender
     * 
     * @param value_ value to transfer
     */
    function getValue(uint256 value_) external {
        require(gateKeeper == msg.sender, "NativeTreasury: only gateKeeper");
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
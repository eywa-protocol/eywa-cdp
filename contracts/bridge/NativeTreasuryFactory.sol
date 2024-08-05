// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

import { Clones } from '@openzeppelin/contracts/proxy/Clones.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { NativeTreasury } from './NativeTreasury.sol';
import { INativeTreasury } from '../interfaces/INativeTreasury.sol';
import { INativeTreasuryFactory } from '../interfaces/INativeTreasuryFactory.sol';

contract NativeTreasuryFactory is INativeTreasuryFactory, Ownable {
    address public immutable implementation;

    event TreasuryCreated(address treasury, address treasuryAdmin);

    constructor() {
        implementation = address(new NativeTreasury());
    }

    function createNativeTreasury(
        address treasuryAdmin_
    ) public returns (address) {
        require(treasuryAdmin_ != address(0), "NativeTreasuryFactory: zero address");
        address clone = Clones.clone(implementation);
        INativeTreasury(clone).initialize(treasuryAdmin_, msg.sender);
        emit TreasuryCreated(clone, treasuryAdmin_);
        return clone;
    }

}
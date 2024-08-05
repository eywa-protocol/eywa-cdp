// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;

interface INativeTreasury {

    function getValue(uint256 value_) external;

    function initialize(address admin, address gateKeeper) external;
}
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;

interface INativeTreasury {
    function callFromTreasury(
        uint256 value_,
        bytes memory data,
        address toSend,
        uint256 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) external;

    function getValue(uint256 value_) external;
}
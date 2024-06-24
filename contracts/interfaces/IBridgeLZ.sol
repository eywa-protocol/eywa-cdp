// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;

interface IBridgeLZ {

    function sendFromTreasury(
        bytes memory data,
        address toReceive,
        uint64 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) external payable returns (bool);

    function chainIds(uint32) external returns(uint64);

}

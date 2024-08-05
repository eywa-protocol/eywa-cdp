// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

interface IGateKeeper {

    function calculateCost(
        address payToken,
        uint256 dataLength,
        uint64 chainIdTo,
        address sender
    ) external view returns (uint256 amountToPay);

    function sendData(
        bytes calldata data,
        address to,
        uint64 chainIdTo,
        bytes memory options
    ) external;

    function treasuries(address sender) external returns (address treasury);
    function bridgePriorities(address bridge) external returns (uint8 priority);
}
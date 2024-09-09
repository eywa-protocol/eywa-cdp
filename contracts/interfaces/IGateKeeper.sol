// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

interface IGateKeeper {

    function calculateAdditionalFee(
        uint256 dataLength,
        uint64 chainIdTo,
        address bridge,
        address sender
    ) external view returns (uint256 amountToPay);

    function sendData(
        bytes calldata data,
        address to,
        uint64 chainIdTo,
        bytes[] memory options
    ) external;

    function nonces(address protocol) external view returns (uint256 nonce);

    function treasuries(address protocol) external returns (address treasury);
}
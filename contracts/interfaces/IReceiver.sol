// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.20;


interface IReceiver {
    function receiveData(bytes32 sender, uint64 chainIdFrom, bytes memory receivedData, bytes32 requestId) external;
    function receiveHash(bytes32 sender, uint64 chainIdFrom, bytes32 receivedHash, bytes32 requestId) external;
}

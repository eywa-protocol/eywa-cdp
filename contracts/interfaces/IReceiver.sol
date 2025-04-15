// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.17;


interface IReceiver {
    function receiveData(bytes32 sender, bytes memory receivedData, bytes32 requestId) external;
    function receiveHash(bytes32 sender, bytes32 receivedHash, bytes32 requestId) external;
}

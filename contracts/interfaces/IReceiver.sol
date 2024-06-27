// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.17;


interface IReceiver {
    function receiveData(address sender, bytes memory receivedData) external;
    function receiveHashData(address sender, bytes32 receivedHash) external;
}

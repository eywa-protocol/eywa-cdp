// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;

interface IReceiveUln {
    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external;
}
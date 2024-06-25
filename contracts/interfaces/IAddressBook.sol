// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;

interface IAddressBook {

    function getDestinationBridge(address sourceBridge_, uint64 chainIdTo) external returns(address);

    function router(uint64 chainId) external returns(address);
    function gateKeeper() external returns(address);
    function receiver() external returns(address);
}

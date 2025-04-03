// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.17;

interface IChainIdAdapter {

    function chainIdToDstEid(uint64 chainId) external view returns(uint32);
    function dstEidToChainId(uint32 dstEid) external view returns(uint64);

}

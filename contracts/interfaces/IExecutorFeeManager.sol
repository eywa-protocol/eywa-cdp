// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.20;


interface IExecutorFeeManager {

    function estimateExecutorGasFee(uint64 chainIdTo, bytes memory options) external view returns(uint256);

    function payExecutorGasFee(bytes32 sentHash, uint64 chainIdTo, bytes memory options, address refundTarget) external payable;

}

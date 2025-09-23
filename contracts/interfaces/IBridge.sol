// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.20;


interface IBridge {

    enum State { 
        Active, // data send and receive possible
        Inactive, // data send and receive impossible
        Limited // only data receive possible
    }

    struct SendParams {
        /// @param requestId unique request ID
        bytes32 requestId;
        /// @param data call data
        bytes data;
        /// @param to receiver contract address
        bytes32 to;
        /// @param chainIdTo destination chain ID
        uint64 chainIdTo;
    }

    function sendV3(
        SendParams calldata params,
        address sender,
        uint256 nonce,
        bytes memory options
    ) external payable;

    function estimateGasFee(
        SendParams memory  params,
        address sender,
        bytes memory options
    ) external view returns (uint256);
}

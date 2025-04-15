// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.17;



interface IOracle {

    function estimateFeeByChain(
        uint64 chainIdTo,
        uint256 callDataLength,
        uint256 gasExecute
    ) external view returns (uint256 fee, uint256 priceRatio);
}


// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.17;



interface IOracle {

    function getGasPrice(uint64 chainId) external view returns(uint256);

    function getPriceRatio(uint64 chainId) external view returns(uint256);

    function getGasCost(uint64 chainId) external view returns(uint256);

    function getGasPerByte(uint64 chainId) external view returns(uint256);

    function getPrice(uint64 chainId) external view returns(uint256 gasCost, uint256 gasPerByte);

    function getPriceArbitrum() external view returns(uint256, uint256, uint256);
}


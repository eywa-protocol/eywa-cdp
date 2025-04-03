// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

interface IGateKeeper {

    function calculateAdditionalFee(
        uint256 dataLength,
        uint64 chainIdTo,
        address bridge,
        uint256 discountPersentage
    ) external view returns (uint256 amountToPay);

    function sendData(
        bytes calldata data,
        bytes32 to,
        uint64 chainIdTo,
        bytes[] memory options
    ) external;

    function estimateGasFee(
        bytes calldata data,
        bytes32 to,
        uint64 chainIdTo,
        bytes[] memory options
    ) external view returns(uint256);

    function nonces(address protocol) external view returns (uint256 nonce);

    function treasuries(address protocol) external view returns (address treasury);
    function bridge() external view returns(address);
}
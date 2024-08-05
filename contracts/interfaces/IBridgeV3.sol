// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.17;

import './IBridgeV2.sol';

interface IBridgeV3 {

    function sendV3(
        IBridgeV2.SendParams memory params,
        address sender,
        uint256 nonce,
        bytes memory options
    ) external payable;

    function estimateGasFee(
        IBridgeV2.SendParams memory  params,
        address sender,
        bytes memory options
    ) external returns (uint256);

}

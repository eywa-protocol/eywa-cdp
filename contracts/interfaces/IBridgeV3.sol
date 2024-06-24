// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;


interface IBridgeV3 {

    function send(
        bytes memory data,
        address receiver,
        uint64 chainIdTo,
        address destinationExecutor,
        uint256[][] memory spentValue,
        bytes[] memory comissionLZ
    ) external payable returns (bool);


}

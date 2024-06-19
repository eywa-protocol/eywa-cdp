// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;

interface IBridgeV3 {

    enum State { 
        Active, // data send and receive possible
        Inactive, // data send and receive impossible
        Limited // only data receive possible
    }


    function send(
        bytes32 data,
        address toReceive,
        uint256 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) external payable returns (bool);


}

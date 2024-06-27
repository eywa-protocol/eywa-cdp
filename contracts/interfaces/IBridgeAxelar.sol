// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.17;


interface IBridgeAxelar {

    function chainIds(string memory) external returns(uint64);

}

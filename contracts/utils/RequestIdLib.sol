// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.20;

library RequestIdLib {

    bytes32 private constant TYPEHASH = keccak256(
        "CrosschainRequest/v1(uint256 chainIdFrom,bytes32 from,uint256 chainIdTo,bytes32 to,bytes32 salt)"
    );

    function prepareRequestId(
        bytes32 to,
        uint256 chainIdTo,
        bytes32 from,
        uint256 chainIdFrom,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(TYPEHASH, chainIdFrom, from, chainIdTo, to, salt));
    }
}

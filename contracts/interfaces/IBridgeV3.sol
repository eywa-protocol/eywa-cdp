// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.17;

import "../interfaces/IBridge.sol";

interface IBridgeV3 is IBridge {
    
    struct ReceiveParams {
        /// @param blockHeader block header serialization
        bytes blockHeader;
        /// @param merkleProof OracleRequest transaction payload and its Merkle audit path
        bytes merkleProof;
        /// @param votersPubKey aggregated public key of the old epoch participants, who voted for the block
        bytes votersPubKey;
        /// @param votersSignature aggregated signature of the old epoch participants, who voted for the block
        bytes votersSignature;
        /// @param votersMask bitmask of epoch participants, who voted, among all participants
        uint256 votersMask;
    }

    enum ChainType {
        DEFAULT,
        ARBITRUM,
        OPTIMISM
    }

    function receiveV3(ReceiveParams[] calldata params) external returns (bool);

    function nonces(address sender) external returns(uint256);
}

// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.17;


import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { IChainIdAdapter } from "../../interfaces/IChainIdAdapter.sol";


contract ChainIdAdapter is IChainIdAdapter, AccessControlEnumerable {
    

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");


    mapping(uint64 => uint32) public chainIdToDstEid;
    mapping(uint32 => uint64) public dstEidToChainId;

    mapping(uint64 => string) public chainIdToChainName;
    mapping(string => uint64) public chainNameToChainId;

    event DstEidSet(uint32 dstEid, uint64 chainId);
    event ChainNameSet(string chainName, uint64 chainId);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function setDstEids(uint32[] memory dstEids_, uint64[] memory chainIds_) external onlyRole(OPERATOR_ROLE) {
        uint256 length = dstEids_.length;
        require(length == chainIds_.length, "ChainIdAdapter: wrong length");
        for (uint32 i; i < length; ++i) {
            chainIdToDstEid[chainIds_[i]] = dstEids_[i];
            dstEidToChainId[dstEids_[i]] = chainIds_[i];
            emit DstEidSet(dstEids_[i], chainIds_[i]);
        }
    }

    function setChainNames(string[] memory chainNames_, uint64[] memory chainIds_) external onlyRole(OPERATOR_ROLE) {
        uint256 length = chainNames_.length;
        require(length == chainIds_.length, "ChainIdAdapter: wrong length");
        for (uint32 i; i < length; ++i) {
            chainIdToChainName[chainIds_[i]] = chainNames_[i];
            chainNameToChainId[chainNames_[i]] = chainIds_[i];
            emit ChainNameSet(chainNames_[i], chainIds_[i]);
        }
    }



    // TODO add CCIP and Asterism

}

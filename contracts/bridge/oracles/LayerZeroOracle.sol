// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.17;

import { ILayerZeroPriceFeed } from "../../interfaces/ILayerZeroPriceFeed.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IChainIdAdapter } from "../../interfaces/IChainIdAdapter.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";


contract LayerZeroOracle is IOracle, AccessControlEnumerable {
    

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    address public priceFeed;

    address public chainIdAdapter;

    uint128 private constant PRICE_RATIO_DENOMINATOR = 1e20;

    event PriceFeedSet(address);
    event ChainIdAdapterSet(address);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function setPriceFeed(address priceFeed_) external onlyRole(OPERATOR_ROLE) {
        require(priceFeed_ != address(0), "LayerZeroOracle: zero address");
        priceFeed = priceFeed_;
        emit PriceFeedSet(priceFeed_);
    }

    function setChainIdAdapter(address chainIdAdapter_) external onlyRole(OPERATOR_ROLE) {
        chainIdAdapter = chainIdAdapter_;
        emit ChainIdAdapterSet(chainIdAdapter_);
    }

    function estimateFeeByChain(
        uint64 chainIdTo,
        uint256 callDataLength,
        uint256 gasExecute
    ) external view returns (uint256 fee, uint256 priceRatio) {
        uint32 dstEid = IChainIdAdapter(chainIdAdapter).chainIdToDstEid(chainIdTo);
        (fee, priceRatio) = ILayerZeroPriceFeed(priceFeed).estimateFeeByChain(
            uint16(dstEid), 
            callDataLength, 
            gasExecute
        );
    }
}

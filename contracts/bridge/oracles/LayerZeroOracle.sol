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

    function getGasPrice(uint64 chainIdTo) external view returns (uint256) {
        return _getPrice(chainIdTo).gasPriceInUnit;
    }

    function getPriceRatio(uint64 chainIdTo) external view returns (uint256) {
        return _getPrice(chainIdTo).priceRatio;
    }

    function getGasPerByte(uint64 chainIdTo) external view returns (uint256) {
        return _getPrice(chainIdTo).gasPerByte;
    }

    function getGasCost(uint64 chainIdTo) external view returns (uint256) {
        ILayerZeroPriceFeed.Price memory price = _getPrice(chainIdTo);
        return price.gasPriceInUnit * price.priceRatio;
    }

    function getPrice(uint64 chainIdTo) public view returns (uint256, uint256) {
        ILayerZeroPriceFeed.Price memory price = _getPrice(chainIdTo);
        return (price.gasPriceInUnit * price.priceRatio / PRICE_RATIO_DENOMINATOR, price.gasPerByte);
    }

    function getPriceArbitrum() external view returns (uint256, uint256, uint256) {
        ILayerZeroPriceFeed.ArbitrumPriceExt memory arbitrumPrice = ILayerZeroPriceFeed(priceFeed).arbitrumPriceExt();
        uint256 arbitrumCompressionPercent = ILayerZeroPriceFeed(priceFeed).ARBITRUM_COMPRESSION_PERCENT();
        return (arbitrumPrice.gasPerL2Tx, arbitrumPrice.gasPerL1CallDataByte, arbitrumCompressionPercent);
    }

    function _getPrice(uint64 chainIdTo) internal view returns (ILayerZeroPriceFeed.Price memory) {
        uint32 dstEid = IChainIdAdapter(chainIdAdapter).chainIdToDstEid(chainIdTo);
        return ILayerZeroPriceFeed(priceFeed).getPrice(dstEid);
    }
}

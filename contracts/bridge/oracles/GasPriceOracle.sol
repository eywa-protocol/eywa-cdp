// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.17;

import { IOracle } from "../../interfaces/IOracle.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";


contract GasPriceOracle is IOracle, AccessControlEnumerable {
    
    mapping(uint64 => address) public gasPriceOracles;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint64 constant CHAIN_ID_ARBITRUM = 42161;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    // TODO may add default gasOracle to save gas
    function setGasPriceOracle(uint64 chainId, address gasPriceOracle) external onlyRole(OPERATOR_ROLE) {
        require(gasPriceOracle != address(0), "GasPriceOracle: zero address");
        gasPriceOracles[chainId] = gasPriceOracle;
    }

    function getGasPrice(uint64 chainIdTo) external view returns (uint256) {
        return IOracle(gasPriceOracles[chainIdTo]).getGasPrice(chainIdTo);
    }

    function getPriceRatio(uint64 chainIdTo) external view returns (uint256) {
        return IOracle(gasPriceOracles[chainIdTo]).getPriceRatio(chainIdTo);
    }

    function getGasPerByte(uint64 chainIdTo) external view returns (uint256) {
        return IOracle(gasPriceOracles[chainIdTo]).getGasPerByte(chainIdTo);
    }

    function getGasCost(uint64 chainIdTo) external view returns (uint256) {
        return IOracle(gasPriceOracles[chainIdTo]).getGasCost(chainIdTo);
    }

    function getPrice(uint64 chainIdTo) external view returns (uint256, uint256) {
        return IOracle(gasPriceOracles[chainIdTo]).getPrice(chainIdTo);
    }

    function getPriceArbitrum() external view returns (uint256, uint256, uint256) {
        return IOracle(gasPriceOracles[CHAIN_ID_ARBITRUM]).getPriceArbitrum();
    }
}



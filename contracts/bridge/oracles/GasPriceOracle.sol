// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
pragma solidity ^0.8.20;

import { IOracle } from "../../interfaces/IOracle.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";


contract GasPriceOracle is IOracle, AccessControlEnumerable {
    
    mapping(uint64 => address) public gasPriceOracles;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    // TODO may add default gasOracle to save gas
    function setGasPriceOracle(uint64 chainId, address gasPriceOracle) external onlyRole(OPERATOR_ROLE) {
        require(gasPriceOracle != address(0), "GasPriceOracle: zero address");
        gasPriceOracles[chainId] = gasPriceOracle;
    }

    function estimateFeeByChain(
        uint64 chainIdTo,
        uint256 callDataLength,
        uint256 gasExecute
    ) external view returns (uint256 fee, uint256 priceRatio) {
        return IOracle(gasPriceOracles[chainIdTo]).estimateFeeByChain(
            chainIdTo, 
            callDataLength, 
            gasExecute
        );
    }
}



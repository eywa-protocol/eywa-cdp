// // SPDX-License-Identifier: UNLICENSED
// // Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved
// pragma solidity ^0.8.17;

// import { IOracle } from "../../interfaces/IOracle.sol";
// import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";


// contract EywaOracle is IOracle, AccessControlEnumerable {
//     mapping(uint64 => uint256) public gasPrice;

//     bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

//     constructor() {
//         _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
//     }

//     function setGasPrice(
//         uint64 chainId_,
//         uint256 gasPrice_
//     ) external onlyRole(OPERATOR_ROLE) {
//         gasPrice[chainId_] = gasPrice_;
//     }

//     function getGasPrice(uint64 chainId) external view returns (uint256) {
//         return gasPrice[chainId];
//     }

//     function getPriceRatio(
//         uint64 chainId
//     ) external view override returns (uint256) {}

//     function getGasCost(
//         uint64 chainId
//     ) external view override returns (uint256) {}

//     function getPrice(
//         uint64 chainId
//     )
//         external
//         view
//         override
//         returns (uint256 gasPrice, uint256 priceRatio, uint256 gasCost)
//     {}

//     function getGasPerByte(
//         uint64 chainId
//     ) external view override returns (uint256) {}
// }

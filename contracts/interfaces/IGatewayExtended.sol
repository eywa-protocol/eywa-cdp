// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@routerprotocol/evm-gateway-contracts/contracts/IGateway.sol";

interface IGatewayExtended is IGateway {
    function iSendDefaultFee() external view returns (uint256);
} 
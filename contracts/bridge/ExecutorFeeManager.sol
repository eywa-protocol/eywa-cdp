// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { IExecutorFeeManager } from "../interfaces/IExecutorFeeManager.sol";
import { IOracle } from "../interfaces/IOracle.sol";

contract ExecutorFeeManager is IExecutorFeeManager, AccessControlEnumerable {

    uint256 constant public CALLDATA_LENGTH = 0;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address public priceOracle;

    event PriceOracleSet(address);
    event ExecutorFeePaid(bytes32 requestId, uint64 chainIdTo, bytes options, uint256 fee);
    event ValueWithdrawn(address to, uint256 amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function setPriceOracle(address priceOracle_) external onlyRole(OPERATOR_ROLE) {
        priceOracle = priceOracle_;
        emit PriceOracleSet(priceOracle_);
    }

    function estimateExecutorGasFee(uint64 chainIdTo, bytes memory options) public view returns(uint256) {
        uint32 gasExecute = abi.decode(options, (uint32));
        (uint256 fee,) = IOracle(priceOracle).estimateFeeByChain(
            chainIdTo, 
            CALLDATA_LENGTH, 
            gasExecute
        );
        return fee;
    }

    function payExecutorGasFee(bytes32 requestId, uint64 chainIdTo, bytes memory options) external payable {
        uint256 fee = estimateExecutorGasFee(chainIdTo, options);
        require(msg.value >= fee, "Executor: not enough value");
        emit ExecutorFeePaid(requestId, chainIdTo, options, fee);
    }

    /**
     * @dev Withdraw value from this contract.
     *
     * @param value_ Amount of value
     */
    function withdrawValue(uint256 value_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success, ) = msg.sender.call{value: value_}("");
        require(success, "BridgeV3: failed to send Ether");
        emit ValueWithdrawn(msg.sender, value_);
    }
}

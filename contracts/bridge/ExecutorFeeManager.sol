// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { IExecutorFeeManager } from "../interfaces/IExecutorFeeManager.sol";
import { IOracle } from "../interfaces/IOracle.sol";

contract ExecutorFeeManager is IExecutorFeeManager, AccessControlEnumerable {

    uint256 constant public CALLDATA_LENGTH = 0;
    bytes32 constant public OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 constant public EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    address public priceOracle;
    mapping(bytes32 => uint256) public paidFees;
    mapping(bytes32 => address) public refundTargets;
    mapping(address => bool) public authorizedRefundTargetSetters;

    event PriceOracleSet(address);
    event ExecutorFeePaid(bytes32 requestId, uint64 chainIdTo, bytes options, uint256 fee, address refundTarget);
    event ValueWithdrawn(address to, uint256 amount);
    event FeeRefunded(bytes32 requestId, address to, uint256 amount);
    event AuthorizedRefundTargetSetterSet(address setter, bool authorized);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    receive() external payable {}

    function setPriceOracle(address priceOracle_) external onlyRole(OPERATOR_ROLE) {
        priceOracle = priceOracle_;
        emit PriceOracleSet(priceOracle_);
    }

    function setAuthorizedRefundTargetSetter(address setter, bool authorized) external onlyRole(OPERATOR_ROLE) {
        authorizedRefundTargetSetters[setter] = authorized;
        emit AuthorizedRefundTargetSetterSet(setter, authorized);
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

    function payExecutorGasFee(bytes32 requestId, uint64 chainIdTo, bytes memory options, address refundTarget) external payable {
        uint256 fee = estimateExecutorGasFee(chainIdTo, options);
        require(msg.value >= fee, "ExecutorFeeManager: not enough value");
        paidFees[requestId] += msg.value;
        
        if (refundTargets[requestId] == address(0)) {
            require(refundTarget != address(0), "ExecutorFeeManager: Invalid refund target");
            require(authorizedRefundTargetSetters[msg.sender], "ExecutorFeeManager: Unauthorized to set refund target");
            refundTargets[requestId] = refundTarget;
        }
        emit ExecutorFeePaid(requestId, chainIdTo, options, fee, refundTargets[requestId]);
    }

    function refund(bytes32 requestId, uint256 amount) external onlyRole(EXECUTOR_ROLE) {
        uint256 maxRefund = paidFees[requestId];
        address to = refundTargets[requestId];

        require(amount <= maxRefund, "ExecutorFeeManager: excess amount");
        require(to != address(0), "ExecutorFeeManager: No refund target set");

        paidFees[requestId] = 0;
        refundTargets[requestId] = address(0);

        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "ExecutorFeeManager: failed to send Ether");

        emit FeeRefunded(requestId, to, amount);
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

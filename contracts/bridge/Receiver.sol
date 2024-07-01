// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/IAddressBook.sol";

contract Receiver is IReceiver, AccessControlEnumerable {

    using Address for address;

    /// @dev bridge role id
    bytes32 public constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev hash -> receives count
    mapping(bytes32 => uint8) public payloadThreshold;
    /// @dev hash -> data
    mapping(bytes32 => bytes) public payload;
    /// @dev protocol -> threshold
    mapping(address => uint8) public threshold;
    /// @dev receivers count
    uint8 public receiversCount;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        receiversCount = 1;
    }

    /**
     * @notice Sets sender's threshold. Must be the same on the sender's side.
     *
     * @param sender The protocol contract address;
     * @param threshold_ The threshold for the given contract address.
     */
    function setThreshold(address sender, uint8 threshold_) external onlyRole(OPERATOR_ROLE) {
        require(threshold_ >= 1, "Receiver: wrong threshold");
        require(threshold_ <= receiversCount, "Receiver: wrong threshold");
        threshold[sender] = threshold_;
    }

    /**
     * @notice Sets enabled bridges count.
     *
     * @param receiversCount_ The bridges count.
     */
    function setReceiversCount(uint8 receiversCount_) external onlyRole(OPERATOR_ROLE) {
        require(receiversCount_ >= 1, "Receiver: wrong receivers count");
        receiversCount = receiversCount_;
    }

    function receiveData(address sender, bytes memory receivedData) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = threshold[sender];
        require(threshold_ > 0, "Receiver: threshold is not set");
        bytes32 hash_ = keccak256(receivedData);
        if (payloadThreshold[hash_] + 1 >= threshold_) {
            _call(receivedData);
            delete payloadThreshold[hash_];
        } else {
            payload[hash_] = receivedData;
        }
    }

    function receiveHashData(address sender, bytes32 receivedHash) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = threshold[sender];
        require(threshold_ > 0, "Receiver: threshold is not set");
        if (payload[receivedHash].length != 0 && payloadThreshold[receivedHash] + 2 >= threshold_) {
            _call(payload[receivedHash]);
            delete payload[receivedHash];
            delete payloadThreshold[receivedHash];
        }
        else {
            payloadThreshold[receivedHash]++;
        }
    }

    function _call(bytes memory receivedData) internal {
        (
            bytes memory dataWithSpendings,
            bytes memory check,
            uint256 nonce,
            address executor
        ) = abi.decode(receivedData, (bytes, bytes, uint256, address));

        bytes memory result = executor.functionCall(check);
        require(abi.decode(result, (bool)), "Receiver: check failed");
        executor.functionCall(dataWithSpendings, "Receiver: receive failed");
    }
}
// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/IAddressBook.sol";

contract Receiver is IReceiver, AccessControlEnumerable {

    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev bridge role id
    bytes32 public constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev hash -> receiver's addresses from where hash received
    mapping(bytes32 => EnumerableSet.AddressSet) internal _hashReceivers;
    /// @dev hash -> data
    mapping(bytes32 => bytes) public payload;
    /// @dev protocol -> threshold
    mapping(address => uint8) public threshold;
    /// @dev hash -> execute status
    mapping(bytes32 => bool) public executedData;
    /// @dev receivers count
    uint8 public receiversCount;

    event ThresholdSet(address sender, uint8 threshold);
    event ReceiverCountSet(uint8 receiverCount);
    event RequestExecuted(bytes32 requestId);

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
        emit  ThresholdSet(sender, threshold_);
    }

    /**
     * @notice Sets enabled bridges count.
     *
     * @param receiversCount_ The bridges count.
     */
    function setReceiversCount(uint8 receiversCount_) external onlyRole(OPERATOR_ROLE) {
        require(receiversCount_ >= 1, "Receiver: wrong receivers count");
        receiversCount = receiversCount_;
        emit ReceiverCountSet(receiversCount_);
    }

    /**
     * @dev Receive full data
     * 
     * @param sender Source sender
     * @param receivedData Received data
     */
    function receiveData(address sender, bytes memory receivedData, bytes32 requestId) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = threshold[sender];
        require(threshold_ > 0, "Receiver: threshold is not set");
        bytes32 hash_ = keccak256(receivedData);
        if(_hashReceivers[hash_].contains(msg.sender)) {
            if(_execute(_hashReceivers[hash_].length(), threshold_, receivedData, hash_)){
                emit RequestExecuted(requestId);
                return;
            }
        } else {
            if(_execute(_hashReceivers[hash_].length() + 1, threshold_, receivedData, hash_)){
                emit RequestExecuted(requestId);
                return;
            }
            _hashReceivers[hash_].add(msg.sender);
        }

        if (payload[hash_].length == 0) {
            payload[hash_] = receivedData;
        } else {
            revert("Receiver: already received");
        }
    }

    /**
     * @dev Receive hash of data
     * 
     * @param sender Source sende
     * @param receivedHash Received hash
     */
    function receiveHashData(address sender, bytes32 receivedHash, bytes32 requestId) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = threshold[sender];
        require(threshold_ > 0, "Receiver: threshold is not set");
        require(!_hashReceivers[receivedHash].contains(msg.sender), "Receiver: already received");
        if (
            _execute(
                _hashReceivers[receivedHash].length() + 1,
                threshold_,
                payload[receivedHash],
                receivedHash
            )
        ) {
            emit RequestExecuted(requestId);
        } else {
            _hashReceivers[receivedHash].add(msg.sender);
        }
    }

    function hashReceivers(bytes32 hash_) public view returns (address[] memory) {
        return _hashReceivers[hash_].values();
    }

    /**
     * @dev Make threshold check and after two calls to executor contract. First for check, second for execute.
     * 
     * @param currentThreshold current threshold
     * @param targetThreshold target threshold
     * @param receivedData data, which fill be decoded and executed
     * @param hash_ hash of receivedData
     */
    function _execute(
        uint256 currentThreshold, 
        uint256 targetThreshold, 
        bytes memory receivedData, 
        bytes32 hash_
    ) internal returns(bool) {
        require(executedData[hash_] == false, "Receiver: already executed");
        if (currentThreshold >= targetThreshold) {
            executedData[hash_] = true;
            (
                bytes memory data,
                bytes memory check,
                uint256 nonce,
                address executor
            ) = abi.decode(receivedData, (bytes, bytes, uint256, address));
            bytes memory result = executor.functionCall(check);
            require(abi.decode(result, (bool)), "Receiver: check failed");
            executor.functionCall(data, "Receiver: receive failed");
            _eraseEnumerableSet(_hashReceivers[hash_]);
            delete _hashReceivers[hash_];
            delete payload[hash_];
            return true;
        }
    }

    /**
     * @dev Make two calls to executor contract. First for check, second for execute.
     * 
     * @param receivedData data, which fill be decoded and executed
     */
    function _call(bytes memory receivedData) internal {

    }

    function _eraseEnumerableSet(EnumerableSet.AddressSet storage set) internal {
        for (uint256 i = set.length(); i > 0; i--) {
            set.remove(set.at(i - 1));
        }
    }
}
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
    event Received(bytes32 requestId, bool isHash);

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
        bytes32 hashKey = _generateHashKey(keccak256(receivedData), sender, requestId);
        if(_hashReceivers[hashKey].contains(msg.sender)) {
            if(_execute(_hashReceivers[hashKey].length(), threshold_, receivedData, hashKey, requestId)){
                emit Received(requestId, false);
                return;
            }
        } else {
            if(_execute(_hashReceivers[hashKey].length() + 1, threshold_, receivedData, hashKey, requestId)){
                emit Received(requestId, false);
                return;
            }
            _hashReceivers[hashKey].add(msg.sender);
        }

        if (payload[hashKey].length == 0) {
            payload[hashKey] = receivedData;
        } else {
            revert("Receiver: already received");
        }
        emit Received(requestId, false);
    }

    /**
     * @dev Receive hash of data
     * 
     * @param sender Source sende
     * @param receivedHash Received hash
     */
    function receiveHash(address sender, bytes32 receivedHash, bytes32 requestId) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = threshold[sender];
        require(threshold_ > 0, "Receiver: threshold is not set");
        bytes32 hashKey = _generateHashKey(receivedHash, sender, requestId);
        require(!_hashReceivers[hashKey].contains(msg.sender), "Receiver: already received");
        if (
            !_execute(
                _hashReceivers[hashKey].length() + 1,
                threshold_,
                payload[hashKey],
                hashKey, 
                requestId
            )
        ) {
            _hashReceivers[hashKey].add(msg.sender);
        }
        emit Received(requestId, true);
    }

    /**
     * @dev Execute if enough threshold
     * 
     * @param hash_ hash
     * @param sender_ source chain bridge caller
     * @param requestId_ request id
     */
    function execute(bytes32 hash_, address sender_, bytes32 requestId_) external {
        bytes32 hashKey = _generateHashKey(hash_, sender_, requestId_);
        bytes memory receivedData = payload[hashKey];
        require(receivedData.length != 0, "Receiver: data not received");
        if (!_execute(_hashReceivers[hashKey].length(), threshold[sender_], receivedData, hashKey, requestId_)) {
            revert("Receiver: not executed");
        }
    }

    function hashReceivers(bytes32 hash_, address sender_, bytes32 requestId_) public view returns (address[] memory) {
        bytes32 hashKey = _generateHashKey(hash_, sender_, requestId_);
        return _hashReceivers[hashKey].values();
    }

    /**
     * @dev Make threshold check and after two calls to executor contract. First for check, second for execute.
     * 
     * @param currentThreshold current threshold
     * @param targetThreshold target threshold
     * @param receivedData data, which fill be decoded and executed
     * @param hashKey hash key consisting of hash, protocol and requestId
     */
    function _execute(
        uint256 currentThreshold, 
        uint256 targetThreshold, 
        bytes memory receivedData, 
        bytes32 hashKey,
        bytes32 requestId
    ) internal returns(bool) {
        require(executedData[hashKey] == false, "Receiver: already executed");
        if (currentThreshold >= targetThreshold) {
            executedData[hashKey] = true;
            (
                bytes memory data,
                bytes memory check,
                uint256 nonce,
                address executor
            ) = abi.decode(receivedData, (bytes, bytes, uint256, address));
            bytes memory result = executor.functionCall(check);
            require(abi.decode(result, (bool)), "Receiver: check failed");
            executor.functionCall(data, "Receiver: receive failed");
            _eraseEnumerableSet(_hashReceivers[hashKey]);
            delete _hashReceivers[hashKey];
            delete payload[hashKey];
            emit RequestExecuted(requestId);
            return true;
        }
    }

    function _eraseEnumerableSet(EnumerableSet.AddressSet storage set) internal {
        for (uint256 i = set.length(); i > 0; i--) {
            set.remove(set.at(i - 1));
        }
    }

    function _generateHashKey(bytes32 hash_, address sender_, bytes32 requestId_) internal pure returns(bytes32) {
        return keccak256(abi.encode(hash_, sender_, requestId_));
    }
}
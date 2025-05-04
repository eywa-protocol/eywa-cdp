// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/IAddressBook.sol";

contract Receiver is IReceiver, AccessControlEnumerable {

    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    /// @dev bridge role id
    bytes32 public constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev hash -> receiver's addresses from where hash received
    mapping(bytes32 => EnumerableSet.AddressSet) internal _hashReceivers;
    /// @dev hash -> data
    mapping(bytes32 => bytes) public payload;
    /// @dev protocol -> threshold
    EnumerableMap.Bytes32ToUintMap private _threshold;
    /// @dev hash -> execute status
    mapping(bytes32 => bool) public executedData;
    /// @dev receivers count
    uint8 public receiversCount;

    event ThresholdSet(bytes32[] sender, uint64[] chainIdFrom, uint8[] threshold);
    event ReceiverCountSet(uint8 receiverCount);
    event RequestExecuted(bytes32 requestId);
    event Received(address receiver, bytes32 requestId, bool isHash);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        receiversCount = 1;
    }

    /**
     * @notice Sets multiple sender's threshold. Must be the same on the sender's side.
     *
     * @param sender The protocol contract addresses;
     * @param chainIdFrom The chain id from for the given contract addresses.
     * @param threshold_ The thresholds for the given contract addresses.
     */
    function setThreshold(bytes32[] memory sender, uint64[] memory chainIdFrom, uint8[] memory threshold_) external onlyRole(OPERATOR_ROLE) {
        uint8 length = uint8(sender.length);
        require(length == threshold_.length, "Receiver: wrong count");
        require(length == chainIdFrom.length, "Receiver: wrong count");
        for (uint8 i; i < length; ++i) {
            require(threshold_[i] >= 1, "Receiver: wrong threshold");
            require(threshold_[i] <= receiversCount, "Receiver: wrong threshold");
            _threshold.set(_packKey(sender[i], chainIdFrom[i]), threshold_[i]);
        }
        emit ThresholdSet(sender, chainIdFrom, threshold_);
    }

    /**
     * @notice Sets enabled bridges count.
     *
     * @param receiversCount_ The bridges count.
     */
    function setReceiversCount(uint8 receiversCount_) external onlyRole(OPERATOR_ROLE) {
        require(receiversCount_ >= 1, "Receiver: wrong receivers count");
        uint256 thresholdLength_ = thresholdLength();
        uint8 threshold_;
        for(uint32 i; i < thresholdLength_; ++i) {
            (, threshold_) = thresholdAt(i);
            require(threshold_ <= receiversCount_, "Receiver: threshold bigger than receiversCount");
        }
        receiversCount = receiversCount_;
        emit ReceiverCountSet(receiversCount_);
    }

    /**
     * @notice Get threshold for given address.
     *
     * @param sender sender address
     */
    function getThreshold(bytes32 sender, uint64 chainIdFrom) public view returns (uint8) {
        (bool exists, uint256 value) = _threshold.tryGet(_packKey(sender, chainIdFrom));
        require(exists, "Receiver: Threshold not set");
        return uint8(value);
    }

    /**
     * @notice Get threshold at index.
     *
     * @param index index
     */
    function thresholdAt(uint256 index) public view returns (bytes32, uint8) {
        (bytes32 key, uint256 value) = _threshold.at(index);
        return (key, uint8(value));
    }

    function thresholdLength() public view returns (uint256) {
        return _threshold.length();
    }

    /**
     * @dev Receive full data.
     * 
     * @param sender Source sender
     * @param receivedData Received data
     */
    function receiveData(bytes32 sender, uint64 chainIdFrom, bytes memory receivedData, bytes32 requestId) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = getThreshold(sender, chainIdFrom);
        require(threshold_ > 0, "Receiver: threshold is not set");
        bytes32 hashKey = _generateHashKey(keccak256(receivedData), sender, requestId);
        if(_hashReceivers[hashKey].contains(msg.sender)) {
            if(_execute(_hashReceivers[hashKey].length(), threshold_, receivedData, hashKey, requestId)){
                emit Received(msg.sender, requestId, false);
                return;
            }
        } else {
            if(_execute(_hashReceivers[hashKey].length() + 1, threshold_, receivedData, hashKey, requestId)){
                emit Received(msg.sender, requestId, false);
                return;
            }
            _hashReceivers[hashKey].add(msg.sender);
        }

        if (payload[hashKey].length == 0) {
            payload[hashKey] = receivedData;
        } else {
            revert("Receiver: already received");
        }
        emit Received(msg.sender, requestId, false);
    }

    /**
     * @dev Receive hash of data
     * 
     * @param sender Source sende
     * @param receivedHash Received hash
     */
    function receiveHash(bytes32 sender, uint64 chainIdFrom, bytes32 receivedHash, bytes32 requestId) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = getThreshold(sender, chainIdFrom);
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
        emit Received(msg.sender, requestId, true);
    }

    /**
     * @dev Execute if enough threshold
     * 
     * @param hash_ hash
     * @param sender_ source chain bridge caller
     * @param requestId_ request id
     */
    function execute(bytes32 hash_, bytes32 sender_, uint64 chainIdFrom, bytes32 requestId_) external {
        bytes32 hashKey = _generateHashKey(hash_, sender_, requestId_);
        bytes memory receivedData = payload[hashKey];
        require(receivedData.length != 0, "Receiver: data not received");
        if (!_execute(_hashReceivers[hashKey].length(), getThreshold(sender_, chainIdFrom), receivedData, hashKey, requestId_)) {
            revert("Receiver: not executed");
        }
    }

    /**
     * @dev Returns list of receivers
     * 
     * @param hash_ hash
     * @param sender_ sender address
     * @param requestId_ request id
     */
    function hashReceivers(bytes32 hash_, bytes32 sender_, bytes32 requestId_) public view returns (address[] memory) {
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
            if (receivedData.length == 0) {
                return false;
            }
            executedData[hashKey] = true;
            (
                bytes memory data,
                bytes memory check,
                uint256 nonce,
                bytes32 executor_
            ) = abi.decode(receivedData, (bytes, bytes, uint256, bytes32));
            address executor = address(uint160(uint256(executor_)));
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

    function _generateHashKey(bytes32 hash_, bytes32 sender_, bytes32 requestId_) internal pure returns(bytes32) {
        return keccak256(abi.encode(hash_, sender_, requestId_));
    }

    function _packKey(bytes32 sender_, uint64 chainId_) internal pure returns(bytes32) {
        return keccak256(abi.encode(sender_, chainId_));
    }
}
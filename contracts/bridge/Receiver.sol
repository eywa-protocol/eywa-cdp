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
    mapping(bytes32 => EnumerableSet.AddressSet) internal _payloadThreshold;
    /// @dev hash -> data
    mapping(bytes32 => bytes) public payload;
    /// @dev protocol -> threshold
    mapping(address => uint8) public threshold;
    /// @dev receivers count
    uint8 public receiversCount;

    event ThresholdSet(address sender, uint8 threshold);
    event ReceiverCountSet(uint8 receiverCount);

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
    function receiveData(address sender, bytes memory receivedData) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = threshold[sender];
        require(threshold_ > 0, "Receiver: threshold is not set");
        bytes32 hash_ = keccak256(receivedData);
        
        if(_payloadThreshold[hash_].contains(msg.sender)) {
            if(_checkThreshold(_payloadThreshold[hash_].length(), threshold_, receivedData, hash_)){
                return;
            }
            if (payload[hash_].length == 0) {
                payload[hash_] = receivedData;
            } else {
                revert("Receiver: already received");
            }
        } else {
            if(_checkThreshold(_payloadThreshold[hash_].length() + 1, threshold_, receivedData, hash_)){
                return;
            }
            if (payload[hash_].length == 0) {
                payload[hash_] = receivedData;
            }
            _payloadThreshold[hash_].add(msg.sender);
        }
    }

    function _checkThreshold(
        uint256 currentThreshold, 
        uint256 targetThreshold, 
        bytes memory receivedData, 
        bytes32 hash_
    ) internal returns(bool) {
        if (currentThreshold >= targetThreshold) {
            _call(receivedData);
            _eraseEnumerableSet(_payloadThreshold[hash_]);
            delete _payloadThreshold[hash_];
            delete payload[hash_];
            return true;
        }
    }

    /**
     * @dev Receive hash of data
     * 
     * @param sender Source sende
     * @param receivedHash Received hash
     */
    function receiveHashData(address sender, bytes32 receivedHash) external onlyRole(RECEIVER_ROLE) {
        uint8 threshold_ = threshold[sender];
        require(threshold_ > 0, "Receiver: threshold is not set");
        require(!_payloadThreshold[receivedHash].contains(msg.sender), "Receiver: already received");
        if (payload[receivedHash].length != 0 && _payloadThreshold[receivedHash].length() + 1 >= threshold_) {
            _call(payload[receivedHash]);
            delete payload[receivedHash];
            _eraseEnumerableSet(_payloadThreshold[receivedHash]);
            delete _payloadThreshold[receivedHash];
        }
        else {
            _payloadThreshold[receivedHash].add(msg.sender);
        }
    }

    function payloadThreshold(bytes32 hash_) public view returns (address[] memory) {
        return _payloadThreshold[hash_].values();
    }

    /**
     * @dev Make two calls to executor contract. First for check, second for execute.
     * 
     * @param receivedData data, which fill be decoded and executed
     */
    function _call(bytes memory receivedData) internal {
        (
            bytes memory data,
            bytes memory check,
            uint256 nonce,
            address executor
        ) = abi.decode(receivedData, (bytes, bytes, uint256, address));
        bytes memory result = executor.functionCall(check);
        require(abi.decode(result, (bool)), "Receiver: check failed");
        executor.functionCall(data, "Receiver: receive failed");
    }

    function _eraseEnumerableSet(EnumerableSet.AddressSet storage set) internal {
        for (uint256 i = set.length(); i > 0; i--) {
            set.remove(set.at(i - 1));
        }
    }
}
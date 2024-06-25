// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/IAddressBook.sol";
import "@openzeppelin/contracts/utils/Address.sol";


contract Receiver is IReceiver, AccessControlEnumerable {

    using Address for address;

    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // hash => receives couter
    mapping(bytes32 => uint8) public receivedHashes;

    // hash => main data
    mapping(bytes32 => bytes) public mainData;
    address public addressBook;

    uint8 public threshold = 2;

    constructor(address addressBook_) {
        require(addressBook_ != address(0), "Receiver: zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        addressBook = addressBook_;
    }

    function setAddressBook(address addressBook_) external onlyRole(OPERATOR_ROLE) {
        require(addressBook_ != address(0), "Receiver: zero address");
        addressBook = addressBook_;
    }

    function receiveData(bytes memory receivedData) external onlyRole(BRIDGE_ROLE) {
        bytes32 hash_ = keccak256(receivedData);
        if (receivedHashes[hash_] >= threshold - 1) {
            _call(receivedData);
        } else {
            mainData[hash_] = receivedData;
        }
        
    }

    function receiveHashData(bytes memory receivedData) external onlyRole(BRIDGE_ROLE) {
        if (mainData[bytes32(receivedData)].length != 0) {
            _call(mainData[bytes32(receivedData)]);
        }
        else {
            receivedHashes[bytes32(receivedData)]++;
        }
    }

    function _call(bytes memory receivedData) internal {
        (bytes memory payload, address executor) = abi.decode(receivedData, (bytes, address));
        (bytes memory data, bytes memory check) = abi.decode(payload, (bytes, bytes));
        bytes memory result = executor.functionCall(check);
        require(abi.decode(result, (bool)), "Bridge: check failed");
        executor.functionCall(data, "Receiver: receive failed");
    }
}
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

    // hash => receives couter
    mapping(bytes32 => uint8) public receivedHashes;

    // hash => main data
    mapping(bytes32 => bytes) public mainData;
    address public addressBook;

    uint8 public treshold = 2;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function receiveData(bytes memory receivedData) external onlyRole(BRIDGE_ROLE) {
        if (receivedData.length == 32) {
            if (mainData[keccak256(receivedData)].length != 0) {
                _callRouter(receivedData);
            }
            else {
                receivedHashes[bytes32(receivedData)]++;
            }
        } else {
            bytes32 hash_ = keccak256(receivedData);
            if (receivedHashes[hash_] >= treshold - 1) {
                _callRouter(receivedData);
            } else {
                mainData[hash_] = receivedData;
            }
        }
    }

    function _callRouter(bytes memory receivedData) internal {
        address router = IAddressBook(addressBook).router(uint64(block.chainid));
        (bytes memory data, bytes memory check) = abi.decode(receivedData, (bytes, bytes));

        bytes memory result = router.functionCall(check);
        require(abi.decode(result, (bool)), "Bridge: check failed");

        router.functionCall(data, "Receiver: receive failed");
    }
    
}
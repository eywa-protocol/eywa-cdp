// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OAppReceiver, OAppCore, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeLZ.sol";
import "../interfaces/IAddressBook.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/INativeTreasury.sol";


contract ReceiverLZ is OAppReceiver {
    
    address public receiver;
    constructor(address endpoint_, address owner_, address receiver_) OAppCore(endpoint_, owner_) {
        require(endpoint_ != address(0), "ReceiverLZ: zero address");
        require(owner_ != address(0), "ReceiverLZ: zero address");
        require(receiver_ != address(0), "ReceiverLZ: zero address");
        receiver = receiver_;
    }

    function _lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address executor_,
        bytes calldata extraData_
    ) internal override {
        address originSender = address(uint160(uint256(origin_.sender)));

        if (message_[message_.length - 1] == 0x01){
            (bytes32 payload, bool isHash) = abi.decode(message_, (bytes32, bool));
            IReceiver(receiver).receiveHashData(originSender, bytes32(payload));
        } else if (message_[message_.length - 1] == 0x00) {
            (bytes memory payload, bool isHash) = abi.decode(message_, (bytes, bool));
            IReceiver(receiver).receiveData(originSender, payload);
        } else {
            revert("ReceiverLZ: wrong message");
        }
    }
}

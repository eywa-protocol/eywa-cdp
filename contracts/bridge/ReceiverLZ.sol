// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeLZ.sol";
import "../interfaces/IAddressBook.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/INativeTreasury.sol";
import { OAppReceiver, OAppCore, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

contract ReceiverLZ is OAppReceiver {
    
    address public bridgeLZ;
    address public addressBook;
    constructor(address endpoint_, address owner_, address bridgeLZ_, address addressBook_) OAppCore(endpoint_, owner_) {
        require(endpoint_ != address(0), "ReceiverLZ: zero address");
        require(owner_ != address(0), "ReceiverLZ: zero address");
        require(bridgeLZ_ != address(0), "ReceiverLZ: zero address");
        require(addressBook_ != address(0), "ReceiverLZ: zero address");
        bridgeLZ = bridgeLZ_;
        addressBook = addressBook_;
    }

    function _lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address executor_,
        bytes calldata extraData_
    ) internal override {
        uint64 chainIdFrom = IBridgeLZ(bridgeLZ).chainIds(origin_.srcEid);
        require(
            IAddressBook(addressBook).router(chainIdFrom) == address(uint160(uint256(origin_.sender))),
            "ReceiverLZ: wrong sender"
        );
        (bytes memory data_, address toCall_) = abi.decode(message_, (bytes, address));
        IReceiver(toCall_).receiveData(data_);
    }
}

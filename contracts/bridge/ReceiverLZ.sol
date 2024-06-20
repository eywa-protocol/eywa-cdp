// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeLZ.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/INativeTreasury.sol";
import { OAppReceiver, OAppCore, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

contract ReceiverLZ is OAppReceiver {
    
    constructor(address _endpoint, address _owner) OAppCore(_endpoint, _owner) {
    }

    function _lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address executor_,
        bytes calldata extraData_
    ) internal override {

        // TODO anyone can call it, make checks of source сhain and source address

        (
            bytes32 data_, 
            address toCall_
        ) = abi.decode(message_, (bytes32, address));
        IReceiver(toCall_).receiveData(data_);
    }
}

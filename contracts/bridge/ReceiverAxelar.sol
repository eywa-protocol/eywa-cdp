// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import { AxelarExpressExecutable } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/IBridgeAxelar.sol";
import "../interfaces/IAddressBook.sol";


contract ReceiverAxelar is AxelarExpressExecutable {
    
    address public receiver;
    constructor(address gateway_, address gasService_, address receiver_) AxelarExpressExecutable(gateway_) {
        require(gateway_ != address(0), "ReceiverAxelar: zero address");
        require(gasService_ != address(0), "ReceiverAxelar: zero address");
        require(receiver_ != address(0), "ReceiverAxelar: zero address");
        receiver = receiver_;
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload_
    ) internal override {
        address originSender = _convertStringToAddress(sourceAddress);
        (bytes memory payload, bool isHash) = abi.decode(payload_, (bytes, bool));
        if (isHash) {
            IReceiver(receiver).receiveHashData(originSender, bytes32(payload));
        } else {
            IReceiver(receiver).receiveData(originSender, payload);
        }
    }

    function _convertStringToAddress(string memory str) private returns(address) {
        return address(bytes20(bytes(str)));
    }
}

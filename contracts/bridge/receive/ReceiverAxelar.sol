// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import { AxelarExpressExecutable } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol";
import { StringToAddress, AddressToString } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressString.sol";
import "../../interfaces/IReceiver.sol";
import "../../interfaces/IAddressBook.sol";


contract ReceiverAxelar is AxelarExpressExecutable {

    using StringToAddress for string;
    
    /// @dev address of main receiver, that stores data and hashes
    address public receiver;
    constructor(address gateway_, address gasService_, address receiver_) AxelarExpressExecutable(gateway_) {
        require(gateway_ != address(0), "ReceiverAxelar: zero address");
        require(gasService_ != address(0), "ReceiverAxelar: zero address");
        require(receiver_ != address(0), "ReceiverAxelar: zero address");
        receiver = receiver_;
    }

    /**
     * @dev Receive payload from Axelar bridge
     * 
     * @param sourceChain source chain
     * @param sourceAddress  sender from source
     * @param payload_ received payload
     */
    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload_
    ) internal override {
        address originSender = sourceAddress.toAddress();
        if (payload_[payload_.length - 1] == 0x01){
            (bytes32 payload, bool isHash) = abi.decode(payload_, (bytes32, bool));
            IReceiver(receiver).receiveHashData(originSender, bytes32(payload));
        } else if (payload_[payload_.length - 1] == 0x00) {
            (bytes memory payload, bool isHash) = abi.decode(payload_, (bytes, bool));
            IReceiver(receiver).receiveData(originSender, payload);
        } else {
            revert("ReceiverAxelar: wrong message");
        }
    }
}

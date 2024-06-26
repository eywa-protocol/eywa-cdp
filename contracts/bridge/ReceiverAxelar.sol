// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import { AxelarExpressExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol';
import "../interfaces/IReceiver.sol";
import "../interfaces/IBridgeAxelar.sol";
import "../interfaces/IAddressBook.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


contract ReceiverAxelar is AxelarExpressExecutable {
    
    address public addressBook;
    address public bridgeAxelar;
    constructor(address gateway_, address gasService_, address bridgeAxelar_, address addressBook_) AxelarExpressExecutable(gateway_) {
        require(gateway_ != address(0), "ReceiverAxelar: zero address");
        require(gasService_ != address(0), "ReceiverAxelar: zero address");
        require(bridgeAxelar_ != address(0), "ReceiverAxelar: zero address");
        require(addressBook_ != address(0), "ReceiverAxelar: zero address");
        addressBook = addressBook_;
        bridgeAxelar = bridgeAxelar_;
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload_
    ) internal override {
        address originSender = _convertStringToAddress(sourceAddress);
        address receiver = IAddressBook(addressBook).receiver();
        (bytes memory payload, bool isHash) = abi.decode(payload_, (bytes, bool));
        if (isHash){
            IReceiver(receiver).receiveHashData(originSender, bytes32(payload));

        } else {
            IReceiver(receiver).receiveData(originSender, payload);
        }
    }

    function _convertStringToAddress(string memory str) private returns(address) {
        return address(bytes20(bytes(str)));
    }
}

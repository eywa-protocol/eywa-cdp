// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import { AxelarExpressExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol';
import "../interfaces/IReceiver.sol";
import "../interfaces/IAddressBook.sol";

contract ReceiverAxelar is AxelarExpressExecutable {
    
    address public addressBook;
    constructor(address gateway_, address gasService_, address addressBook_) AxelarExpressExecutable(gateway_) {
        require(gateway_ != address(0), "GateKeeper: zero address");
        require(gasService_ != address(0), "GateKeeper: zero address");
        require(addressBook_ != address(0), "GateKeeper: zero address");
        addressBook = addressBook_;
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload_
    ) internal override {

        // TODO anyone can call it, make checks of sourceChain and source address

        (
            bytes32 data_, 
            address toCall_
        ) = abi.decode(payload_, (bytes32, address));
        IReceiver(toCall_).receiveData(data_);
    }

    function _convertStringToAddress(string memory str) private returns(address) {
        return address(bytes20(bytes(str)));
    }
}

// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import { AxelarExpressExecutable } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol";
import { StringToAddress, AddressToString } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressString.sol";
import "../../interfaces/IReceiver.sol";
import "../../interfaces/IAddressBook.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";


contract ReceiverAxelar is AxelarExpressExecutable, AccessControlEnumerable {

    using StringToAddress for string;
    
    /// @dev address of main receiver, that stores data and hashes
    address public immutable receiver;

    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(string sourceChain => address peer) public peers;
    event PeerSet(string sourceChain, address peer);

    constructor(address gateway_, address gasService_, address receiver_) AxelarExpressExecutable(gateway_) {
        require(gateway_ != address(0), "ReceiverAxelar: zero address");
        require(gasService_ != address(0), "ReceiverAxelar: zero address");
        require(receiver_ != address(0), "ReceiverAxelar: zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        receiver = receiver_;
    }

    function setPeer(string calldata sourceChain_, address peer_) public onlyRole(OPERATOR_ROLE) {
        peers[sourceChain_] = peer_;
        emit PeerSet(sourceChain_, peer_);
    }

    /**
     * @dev Receive payload from Axelar bridge
     * 
     * @param sourceChain source chain
     * @param sourceAddress  source address, which calls axelar gateway
     * @param payload_ received payload
     */
    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload_
    ) internal override {
        require(peers[sourceChain] == sourceAddress.toAddress(), "ReceiverAxelar: wrong peer");
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

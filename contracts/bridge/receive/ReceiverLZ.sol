// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OAppReceiver, OAppCore, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "../../interfaces/IBridgeV3.sol";
import "../../interfaces/IAddressBook.sol";
import "../../interfaces/IReceiver.sol";
import "../../interfaces/INativeTreasury.sol";
contract ReceiverLZ is OAppReceiver, AccessControlEnumerable {
    
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev address of main receiver, that stores data and hashes
    address public immutable receiver;


    constructor(address endpoint_,  address receiver_) OAppCore(endpoint_, msg.sender) {
        require(endpoint_ != address(0), "ReceiverLZ: zero address");
        require(receiver_ != address(0), "ReceiverLZ: zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        receiver = receiver_;
    }

    /**
     * @dev Set peer for OApp
     * 
     * Required to be set for each EID
     * 
     * @param _eid Eid of chain
     * @param _peer Destination OApp contract address in bytes32 format
     */
    function setPeer(uint32 _eid, bytes32 _peer) public override onlyRole(OPERATOR_ROLE) {
        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    /**
     * @dev Entry point for receiving messages or packets from the endpoint.
     * @param origin_ The origin information containing the source endpoint and sender address.
     *  - srcEid: The source chain endpoint ID.
     *  - sender: The sender address on the src chain.
     *  - nonce: The nonce of the message.
     * @param guid_ The unique identifier for the received LayerZero message.
     * @param message_ The payload of the received message.
     * @param executor_ The address of the executor for the received message.
     * @param extraData_ Additional arbitrary data provided by the corresponding executor.
     */
    function _lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address executor_,
        bytes calldata extraData_
    ) internal override {
        bytes32 requestId;
        bytes32 sender;
        uint256 length = message_.length - 1;
        bytes memory message = new bytes(length);
        for (uint i; i < length; ++i) {
            message[i] = message_[i];
        }
        if (message_[message_.length - 1] == 0x01){
            require(message.length == 96, "ReceiverLZ: Invalid message length");
            bytes32 payload;
            (payload, sender, requestId) = abi.decode(message, (bytes32, bytes32, bytes32));
            IReceiver(receiver).receiveHash(sender, payload, requestId);
        } else if (message_[message_.length - 1] == 0x00) {
            bytes memory payload;
            (payload, sender, requestId) = abi.decode(message, (bytes, bytes32, bytes32));
            IReceiver(receiver).receiveData(sender, payload, requestId);
        } else {
            revert("ReceiverLZ: wrong message");
        }
    }
}

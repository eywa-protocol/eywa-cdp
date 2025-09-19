// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import { StringToAddress } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressString.sol";
import "../../interfaces/IReceiver.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title ReceiverRouter
 * @dev Router Protocol receiver implementation for cross-chain data reception
 * 
 * This contract implements the Router Protocol receiver functionality, handling
 * incoming cross-chain messages and routing them to the appropriate receiver
 * contract. It validates message authenticity and decodes different message types.
 * 
 * Key features:
 * - Peer validation for message authenticity
 * - Support for both data and hash message types
 * - Role-based access control for peer management
 * - Automatic routing to main receiver contract
 * 
 * Message types:
 * - Data messages (0x00): Contains actual data payload
 * - Hash messages (0x01): Contains hash of data for verification
 * 
 * @notice This contract acts as a router between Router Protocol and the main receiver
 * @notice Only authorized peers can send messages to this contract
 * @notice Operators can configure peer addresses for different source chains
 */
contract ReceiverRouter is AccessControlEnumerable {

    using StringToAddress for string;

    /// @dev Address of the main receiver contract that stores data and hashes
    address public immutable receiver;

    /// @dev Operator role identifier - allows peer configuration
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev Router Protocol gateway contract address
    address public gateway;
    
    /// @dev Mapping of source chain identifiers to their peer contract addresses
    mapping(string sourceChain => address peer) public peers;

    /**
     * @dev Emitted when a peer is set for a source chain
     * @param sourceChain The source chain identifier
     * @param peer The peer contract address on the source chain
     */
    event PeerSet(string sourceChain, address peer);

    /**
     * @dev Emitted when the gateway address is updated
     * @param gateway The new gateway contract address
     */
    event GatewaySet(address gateway);

    /**
     * @dev Constructor initializes the receiver router
     * @param receiver_ The main receiver contract address
     * @param gateway_ The Router Protocol gateway contract address
     * @notice The deployer becomes the default admin role holder
     * @notice Receiver and gateway addresses cannot be zero
     */
    constructor(address receiver_, address gateway_) {
        require(receiver_ != address(0), "ReceiverRouter: zero address");
        require(gateway_ != address(0), "ReceiverRouter: zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        receiver = receiver_;
        gateway = gateway_;
    }

    /**
     * @dev Sets the peer contract address for a specific source chain
     * @param sourceChain_ The source chain identifier string
     * @param peer_ The peer contract address on the source chain
     * @notice Only callable by operators
     * @notice Peer address can be zero to disable messages from that chain
     */
    function setPeer(string calldata sourceChain_, address peer_) public onlyRole(OPERATOR_ROLE) {
        peers[sourceChain_] = peer_;
        emit PeerSet(sourceChain_, peer_);
    }

    /**
     * @dev Updates the Router Protocol gateway address
     * @param gateway_ The new gateway contract address
     * @notice Only callable by operators
     * @notice Gateway address cannot be zero
     */
    function setGateway(address gateway_) external onlyRole(OPERATOR_ROLE) {
        require(gateway_ != address(0), "ReceiverRouter: zero address");
        gateway = gateway_;
        emit GatewaySet(gateway_);
    }

    /**
     * @dev Receives and processes cross-chain messages from Router Protocol
     * @param requestSender The address of the sender on the source chain
     * @param packet The encoded message packet containing data and metadata
     * @param srcChainId The source chain identifier
     * @notice This function is called by Router Protocol gateway
     * @notice Validates peer authenticity before processing
     * @notice Supports both data (0x00) and hash (0x01) message types
     * @notice Routes processed messages to the main receiver contract
     */
    function iReceive(
        string memory requestSender,
        bytes calldata packet,
        string memory srcChainId
    ) external {
        require(msg.sender == gateway, "ReceiverRouter: only gateway");
        require(peers[srcChainId] == requestSender.toAddress(), "ReceiverRouter: wrong peer");
        bytes32 requestId;
        bytes32 sender;
        uint256 chainIdFrom;
        bytes calldata data = packet[0 : packet.length - 1];
        if (packet[packet.length - 1] == 0x01) {
            require(data.length == 128, "ReceiverRouter: Invalid message length");
            bytes32 payload;
            (payload, sender, chainIdFrom, requestId) = abi.decode(data, (bytes32, bytes32, uint256, bytes32));
            IReceiver(receiver).receiveHash(sender, uint64(chainIdFrom), payload, requestId);
        } else if (packet[packet.length - 1] == 0x00) {
            bytes memory payload;
            (payload, sender, chainIdFrom, requestId) = abi.decode(data, (bytes, bytes32, uint256, bytes32));
            IReceiver(receiver).receiveData(sender, uint64(chainIdFrom), payload, requestId);
        } else {
            revert("ReceiverRouter: wrong message");
        }
    }
}

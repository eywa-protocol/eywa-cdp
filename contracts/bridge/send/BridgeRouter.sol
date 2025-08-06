// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@routerprotocol/evm-gateway-contracts/contracts/IDapp.sol";
import "../../interfaces/IGatewayExtended.sol";
import "@routerprotocol/evm-gateway-contracts/contracts/Utils.sol";
import { IGateKeeper } from "../../interfaces/IGateKeeper.sol";
import "../../interfaces/IBridge.sol";
import "../../interfaces/INativeTreasury.sol";

/**
 * @title BridgeRouter
 * @dev Router Protocol bridge implementation for cross-chain data transfer
 * 
 * This contract implements the Router Protocol bridge functionality, allowing
 * secure cross-chain communication through the Router Protocol gateway. It
 * supports sending data and hashes to different blockchain networks with
 * configurable parameters and access control.
 * 
 * Key features:
 * - Role-based access control for operators and gatekeepers
 * - Configurable Router Protocol parameters (version, route amount, recipient)
 * - State management for emergency pause functionality
 * - Gas fee estimation for cross-chain transfers
 * - Receiver mapping for different destination chains
 * 
 * @notice This contract requires proper setup of Router Protocol gateway
 * @notice Only authorized gatekeepers can initiate cross-chain transfers
 * @notice Operators can configure bridge parameters and manage state
 */
contract BridgeRouter is IBridge, AccessControlEnumerable, ReentrancyGuard {
    
    using Address for address;
    
    /// @dev Gate keeper role identifier - allows initiating cross-chain transfers
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    
    /// @dev Operator role identifier - allows configuration and management
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @dev Current bridge state - Active allows transfers, Inactive pauses all operations
    IBridge.State public state;
    
    /// @dev Nonce tracking per sender address to prevent replay attacks
    mapping(address => uint256) public nonces;
    
    /// @dev Mapping of destination chain IDs to their receiver contract addresses
    mapping (uint64 => address) public receivers;

    /// @dev Router Protocol gateway contract address
    address public gateway;
    
    /// @dev Router Protocol version for compatibility
    uint256 public routerVersion = 1;
    
    /// @dev Route amount for Router Protocol fee calculation
    uint256 public routerRouteAmount = 0;
    
    /// @dev Route recipient address for Router Protocol fees
    string public routerRouteRecipient = "";

    /**
     * @dev Emitted when the bridge state is changed
     * @param state The new bridge state (Active/Inactive)
     */
    event StateSet(IBridge.State state);
    
    /**
     * @dev Emitted when a receiver is set for a destination chain
     * @param chainIdTo The destination chain ID
     * @param receiver The receiver contract address
     */
    event ReceiverSet(uint64 chainIdTo, address receiver);
    
    /**
     * @dev Emitted when dApp metadata is updated
     * @param feePayer The fee payer identifier
     */
    event DappMetadataSet(string feePayer);
    
    /**
     * @dev Emitted when the gateway address is updated
     * @param gateway The new gateway contract address
     */
    event GatewaySet(address gateway);
    
    /**
     * @dev Emitted when Router Protocol parameters are updated
     * @param version The Router Protocol version
     * @param routeAmount The route amount for fee calculation
     * @param routeRecipient The route recipient address
     */
    event RouterParamsSet(uint256 version, uint256 routeAmount, string routeRecipient);

    /**
     * @dev Constructor initializes the bridge with Router Protocol gateway
     * @param gateway_ The Router Protocol gateway contract address
     * @notice The deployer becomes the default admin role holder
     * @notice Bridge starts in Active state by default
     */
    constructor(address payable gateway_) {
        require(gateway_ != address(0), "BridgeRouter: zero gateway address");
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        state = IBridge.State.Active;
        gateway = gateway_;
    }

    /**
     * @dev Fallback function to receive ETH
     * @notice Allows the contract to receive ETH for fee payments
     */
    receive() external payable {}

    /**
     * @dev Sets the dApp metadata for Router Protocol fee payer configuration
     * @param FeePayer The fee payer identifier string
     * @return The result of the gateway metadata update
     * @notice Only callable by operators
     * @notice Requires msg.value to cover the Gateway's iSendDefaultFee
     */
    function setDappMetadata(
        string memory FeePayer
    ) public payable onlyRole(OPERATOR_ROLE) returns(uint256) {
        require(bytes(FeePayer).length > 0, "BridgeRouter: empty fee payer");
        require(gateway != address(0), "BridgeRouter: gateway not set");
        
        uint256 requiredFee = IGatewayExtended(gateway).iSendDefaultFee();
        require(msg.value == requiredFee, "BridgeRouter: wrong fee");
        
        uint256 result = IGatewayExtended(gateway).setDappMetadata{value: requiredFee}(FeePayer);
        emit DappMetadataSet(FeePayer);
    }

    /**
     * @dev Updates the Router Protocol gateway address
     * @param gateway_ The new gateway contract address
     * @notice Only callable by operators
     * @notice Gateway address cannot be zero
     */
    function setGateway(address gateway_) external onlyRole(OPERATOR_ROLE) {
        require(gateway_ != address(0), "BridgeRouter: zero address");
        gateway = gateway_;
        emit GatewaySet(gateway_);
    }

    /**
     * @dev Sets Router Protocol parameters for cross-chain transfers
     * @param version_ The Router Protocol version for compatibility
     * @param routeAmount_ The route amount for fee calculation
     * @param routeRecipient_ The route recipient address for fees
     * @notice Only callable by operators
     * @notice These parameters affect all cross-chain transfers
     */
    function setRouterParams(
        uint256 version_,
        uint256 routeAmount_,
        string memory routeRecipient_
    ) external onlyRole(OPERATOR_ROLE) {
        routerVersion = version_;
        routerRouteAmount = routeAmount_;
        routerRouteRecipient = routeRecipient_;
        emit RouterParamsSet(version_, routeAmount_, routeRecipient_);
    }

    /**
     * @dev Sets the receiver contract address for a specific destination chain
     * @param chainIdTo_ The destination chain ID
     * @param receiver_ The receiver contract address on the destination chain
     * @notice Only callable by operators
     * @notice Receiver address can be zero to disable transfers to that chain
     */
    function setReceiver(uint64 chainIdTo_, address receiver_) external onlyRole(OPERATOR_ROLE) {
        receivers[chainIdTo_] = receiver_;
        emit ReceiverSet(chainIdTo_, receiver_);
    }

    /**
     * @dev Sets the bridge state for emergency control
     * @param state_ The new bridge state (Active/Inactive)
     * @notice Only callable by operators
     * @notice Inactive state prevents all cross-chain transfers
     * @notice Can be used for emergency pause functionality
     */
    function setState(IBridge.State state_) external onlyRole(OPERATOR_ROLE) {
        state = state_;
        emit StateSet(state);
    }

    /**
     * @dev Gets the required fee for setting dApp metadata from the Gateway
     * @return The required fee in wei for setDappMetadata calls
     * @notice This is a view function that queries the Gateway's iSendDefaultFee
     */
    function getDappMetadataFee() public view returns (uint256) {
        require(gateway != address(0), "BridgeRouter: gateway not set");
        return IGatewayExtended(gateway).iSendDefaultFee();
    }

    /**
     * @dev Estimates Router Protocol fees for cross-chain transfers
     * @param params The send parameters containing destination and data
     * @param sender The protocol address initiating the transfer
     * @param options_ Additional call options encoded as bytes
     * @return The Router Protocol fee
     * @notice This is a view function that doesn't modify state
     * @notice Returns only the current iSendDefaultFee from the Gateway contract
     */
    function estimateGasFee(
        IBridge.SendParams calldata params,
        address sender,
        bytes memory options_
    ) public view returns (uint256) {
        require(gateway != address(0), "BridgeRouter: gateway not set");
        uint256 routerFee = IGatewayExtended(gateway).iSendDefaultFee();
        return routerFee;
    }

    /**
     * @dev Generates request metadata for Router Protocol
     * @param destGasLimit The destination gas limit
     * @param destGasPrice The destination gas price
     * @param ackGasLimit The acknowledgement gas limit
     * @param ackGasPrice The acknowledgement gas price
     * @param relayerFees The relayer fees
     * @param ackType The acknowledgement type
     * @param isReadCall The read call flag
     * @param asmAddress The assembly address
     **/
    function getRequestMetadata(
        uint64 destGasLimit,
        uint64 destGasPrice,
        uint64 ackGasLimit,
        uint64 ackGasPrice,
        uint128 relayerFees,
        uint8 ackType,
        bool isReadCall,
        bytes memory asmAddress
    ) external pure returns (bytes memory) {
        bytes memory requestMetadata = abi.encodePacked(
            destGasLimit,
            destGasPrice,
            ackGasLimit,
            ackGasPrice,
            relayerFees,
            ackType,
            isReadCall,
            asmAddress
        );
        return requestMetadata;
    }
    
    /**
     * @dev Initiates a cross-chain data transfer via Router Protocol
     * @param params The send parameters containing request ID, data, destination, and chain ID
     * @param sender The protocol address initiating the transfer
     * @param nonce The nonce to prevent replay attacks
     * @param options Additional call options for Router Protocol
     * @notice Only callable by gatekeepers
     * @notice Bridge must be in Active state
     * @notice This function is payable to cover Router Protocol fees
     */
    function sendV3(
        IBridge.SendParams calldata params,
        address sender,
        uint256 nonce,
        bytes memory options
    ) public payable onlyRole(GATEKEEPER_ROLE) {
        _send(params, sender, options);
    }

    /**
     * @dev Internal function to execute the cross-chain transfer
     * @param params The send parameters for the transfer
     * @param sender The protocol address initiating the transfer
     * @param options_ The Router Protocol call options
     * @notice This function handles the actual Router Protocol interaction
     * @notice Reverts if bridge is inactive
     * @notice Forwards the iSendDefaultFee to the gateway iSend call
     */
    function _send(
        IBridge.SendParams calldata params,
        address sender,
        bytes memory options_
    ) internal {
        require(state == IBridge.State.Active, "BridgeRouter: state inactive");
        require(gateway != address(0), "BridgeRouter: gateway not set");

        address receiverAddress = receivers[params.chainIdTo];
        require(receiverAddress != address(0), "BridgeRouter: receiver not set for chain");

        string memory destChainId = Strings.toString(params.chainIdTo);
        string memory destinationAddress = Strings.toHexString(uint160(receiverAddress), 20);
        bytes memory payload = abi.encode(destinationAddress, params.data);

        require(gateway != address(0), "BridgeRouter: gateway not set");
        uint256 iSendDefaultFee = IGatewayExtended(gateway).iSendDefaultFee();
        IGatewayExtended(gateway).iSend{value: iSendDefaultFee}(
            routerVersion,
            routerRouteAmount,
            routerRouteRecipient,
            destChainId,
            options_,
            payload
        );
    }
}

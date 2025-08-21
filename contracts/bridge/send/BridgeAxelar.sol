// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import { AxelarExecutable } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { AxelarExpressExecutable } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { IAxelarGasService } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import { IGateKeeper } from "../../interfaces/IGateKeeper.sol";
import "../../interfaces/IBridge.sol";
import "../../interfaces/INativeTreasury.sol";
import "../../interfaces/IChainIdAdapter.sol";


contract BridgeAxelar is AxelarExpressExecutable, IBridge, AccessControlEnumerable, ReentrancyGuard {
    
    using Address for address;
    
    /// @dev gate keeper role id
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev current state Active\Inactive
    IBridge.State public state;
    /// @dev nonces
    mapping(address => uint256) public nonces;
    /// @dev chainIdTo => receiver
    mapping (uint64 => address) public receivers;
    /// @dev Axelar gas service
    IAxelarGasService public immutable gasService;
    /// @dev ChainIdAdapter address
    address public chainIdAdapter;
    /// @dev human readable tag
    string public tag;

    event StateSet(IBridge.State state);
    event NetworkSet(uint64 chainIdTo, string network);
    event ReceiverSet(uint64 chainIdTo, address receiver);
    event ChainIdAdapterSet(address);

    constructor(address gateway_, address gasService_, string memory tag_) AxelarExpressExecutable(gateway_) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        state = IBridge.State.Active;
        tag = tag_;
        gasService = IAxelarGasService(gasService_);
    }

    receive() external payable {}

    /**
     * @dev Set receiver for chainId
     * 
     * @param chainIdTo_ Chain ID of receiver
     */
    function setReceiver(uint64 chainIdTo_, address receiver_) external onlyRole(OPERATOR_ROLE) {
        receivers[chainIdTo_] = receiver_;
        emit ReceiverSet(chainIdTo_, receiver_);
    }

    /**
     * @dev Set ChainIdAdapter address.
     * 
     * @param chainIdAdapter_ ChainIdAdapter address
     */
    function setChainIdAdapter(address chainIdAdapter_) external onlyRole(OPERATOR_ROLE) {
        chainIdAdapter = chainIdAdapter_;
        emit ChainIdAdapterSet(chainIdAdapter_);
    }

    /**
     * @dev Set new state.
     *
     * Controlled by operator. Can be used to emergency pause send or send and receive data.
     *
     * @param state_ Active\Inactive state
     */
    function setState(IBridge.State state_) external onlyRole(OPERATOR_ROLE) {
        state = state_;
        emit StateSet(state);
    }

    /**
     * @notice Estimate gas for a cross-chain contract call
     * @param destinationChain_ name of the dest chain
     * @param destinationAddress_ address on dest chain this tx is going to
     * @param payload_ message to be sent
     * @param gasLimit_ message to be sent
     * @param params_ message to be sent
     * @return gasEstimate The cross-chain gas estimate
     */
    function quote(
        string memory destinationChain_,
        string memory destinationAddress_,
        bytes memory payload_,
        uint256 gasLimit_,
        bytes memory params_
    ) public view returns (uint256) {
        return gasService.estimateGasFee(
            destinationChain_,
            destinationAddress_,
            payload_,
            gasLimit_,
            params_
        );
    }

    /**
     * @dev Estimate price for Axelar bridge
     * 
     * @param params send params
     * @param sender protocol which uses bridge
     * @param options_ additional call options
     */
    function estimateGasFee(
        IBridge.SendParams calldata params,
        address sender,
        bytes memory options_
    ) public view returns (uint256) {
        (
            string memory destinationChain,
            string memory destinationAddress,
            uint256 gasLimit,
            bytes memory options
        ) = _unpackParams(params, options_);

        return gasService.estimateGasFee(
            destinationChain,
            destinationAddress,
            params.data,
            gasLimit,
            options
        );
    }
    
    /**
     * @dev Send params to chainIdTo
     * 
     * @param params  params, which will be sent
     * @param sender  protocol which uses bridge
     * @param nonce  nonce 
     * @param options  additional call options
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
     * @dev Send params to chainIdTo
     * 
     * @param params  params, which will be sent
     * @param sender  protocol which uses bridge
     * @param options_  additional call options
     */
    function _send(
        IBridge.SendParams calldata params,
        address sender,
        bytes memory options_
    ) internal {
        require(state == IBridge.State.Active, "BridgeAxelar: state inactive");

        (
            string memory destinationChain,
            string memory destinationAddress,
            uint256 gasLimit,
            bytes memory options
        ) = _unpackParams(params, options_);
        _payGas(destinationChain, destinationAddress, params.data, gasLimit, sender, options);
        gateway.callContract(
            destinationChain,
            destinationAddress,
            params.data
        );
    }

    /**
     * @dev Unpack params for Axelar bridge usage
     * 
     * @param params send params
     * @param options_ additional options packed
     * @return destinationChain destionation chain in string type
     * @return destinationAddress destination address in string type
     * @return gasLimit gas limit for destination tx
     * @return options additional options for destination call
     */
    function _unpackParams(IBridge.SendParams calldata params, bytes memory options_) internal view
        returns(
            string memory destinationChain,
            string memory destinationAddress,
            uint256 gasLimit,
            bytes memory options
        ) {
            uint64 chainIdTo = uint64(params.chainIdTo);
            require(chainIdAdapter != address(0), "Bridge: chainId adapter not set");
            destinationChain = IChainIdAdapter(chainIdAdapter).chainIdToChainName(chainIdTo);
            destinationAddress = Strings.toHexString(uint160(receivers[chainIdTo]), 20);
            (gasLimit, options) = abi.decode(options_, (uint256, bytes));
        }

    /**
     * @dev Pay gas for Axelar bridge usage
     * 
     * @param chainId chain id to
     * @param destinationAddress destionation address
     * @param data  send data
     * @param gasLimit gas limit of destination tx
     * @param sender protocol address
     * @param options additional options
     */
    function _payGas(
        string memory chainId,
        string memory destinationAddress,
        bytes memory data,
        uint256 gasLimit,
        address sender,
        bytes memory options
    ) internal {
        gasService.payGas{value: msg.value} (
            address(this),
            chainId,
            destinationAddress,
            data,
            gasLimit,
            false,
            sender,
            options
        );
    }
}

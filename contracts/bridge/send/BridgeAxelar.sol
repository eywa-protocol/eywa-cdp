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
import "../../interfaces/IBridgeV3.sol";
import "../../interfaces/IBridgeV2.sol";
import "../../interfaces/INativeTreasury.sol";


contract BridgeAxelar is AxelarExpressExecutable, IBridgeV3, AccessControlEnumerable, ReentrancyGuard {
    
    using Address for address;
    
    /// @dev gate keeper role id
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev current state Active\Inactive
    IBridgeV2.State public state;
    /// @dev nonces
    mapping(address => uint256) public nonces;
    /// @dev chainIdTo => dstEid
    mapping(uint64 => string) public networkById;
    /// @dev chainIdTo => receiver
    mapping (uint64 => address) public receivers;
    /// @dev Axelar gas service
    IAxelarGasService public immutable gasService;

    event StateSet(IBridgeV2.State state);
    event NetworkSet(uint64 chainIdTo, string network);
    event ReceiverSet(uint64 chainIdTo, address receiver);

    constructor(address gateway_, address gasService_) AxelarExpressExecutable(gateway_) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        state = IBridgeV2.State.Active;

        gasService = IAxelarGasService(gasService_);
    }

    /**
     * @dev Set network for chainId
     * 
     * @param chainIdTo_ Chain ID to send
     * @param network_ Network name of chain
     */
    function setDestinationNetwork(uint64 chainIdTo_, string memory network_) external onlyRole(OPERATOR_ROLE) {
        networkById[chainIdTo_] = network_;
        emit NetworkSet(chainIdTo_, network_);
    }

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
     * @dev Set new state.
     *
     * Controlled by operator. Can be used to emergency pause send or send and receive data.
     *
     * @param state_ Active\Inactive state
     */
    function setState(IBridgeV2.State state_) external onlyRole(OPERATOR_ROLE) {
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

    function estimateGasFee(
        IBridgeV2.SendParams calldata params,
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
    

    // /**
    //  * @dev Send data to receiver in chainIdTo
    //  * 
    //  * @param data  data, which will be sent
    //  * @param chainIdTo  destination chain id 
    //  * @param spentValue value which will be spent for axelar delivery
    //  * @param commission gas and eth value for destination execution
    //  */
    function sendV3(
        IBridgeV2.SendParams calldata params,
        address sender,
        uint256 nonce,
        bytes memory options
    ) public payable override onlyRole(GATEKEEPER_ROLE) {
        _send(params, sender, options);
    }

    // /**
    //  * @dev Send data to receiver in chainIdTo
    //  * 
    //  * @param data  data, which will be sent
    //  * @param chainIdTo_  destination chain id 
    //  */
    function _send(
        IBridgeV2.SendParams calldata params,
        address sender,
        bytes memory options_
    ) internal returns (bool) {
        require(state == IBridgeV2.State.Active, "BridgeAxelar: state inactive");

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

    function _unpackParams(IBridgeV2.SendParams calldata params, bytes memory options_) internal view
        returns(
            string memory destinationChain,
            string memory destinationAddress,
            uint256 gasLimit,
            bytes memory options
        ) {
            uint64 chainIdTo = uint64(params.chainIdTo);
            destinationChain = networkById[chainIdTo];
            destinationAddress = Strings.toHexString(uint160(receivers[chainIdTo]), 20);
            (gasLimit, options) = abi.decode(options_, (uint256, bytes));
        }

    function _payGas(
        string memory chainId,
        string memory destinationAddress,
        bytes memory data,
        uint256 gasLimit,
        address sender,
        bytes memory params
    ) internal {
        gasService.payGas{value: msg.value} (
            address(this),
            chainId,
            destinationAddress,
            data,
            gasLimit,
            false,
            sender,
            params
        );
    }

    receive() external payable {

    }
}

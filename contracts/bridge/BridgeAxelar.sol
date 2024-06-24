// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeV2.sol";
import "../interfaces/IBridgeAxelar.sol";
import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { AxelarExpressExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';
import "@openzeppelin/contracts/utils/Strings.sol";
import "../interfaces/INativeTreasury.sol";

contract BridgeAxelar is AxelarExpressExecutable, IBridgeV3, IBridgeAxelar, AccessControlEnumerable, ReentrancyGuard {
    
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
    /// @dev dstEid => chainIdTo
    mapping(string => uint64) public chainIds;
    /// @dev Axelar gas service
    IAxelarGasService public immutable gasService;
    /// @dev native treasury address
    address public treasury;

    event StateSet(IBridgeV2.State state);
    event TreasurySet(address treasury);
    event NetworkSet(uint64 chainIdTo, string network);

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
    function setDestinationNetwork(uint64 chainIdTo_, string memory network_) external {
        networkById[chainIdTo_] = network_;
        chainIds[network_] = chainIdTo_;
        emit NetworkSet(chainIdTo_, network_);
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
     * @dev Set new treasury.
     *
     * Controlled by operator.
     *
     * @param treasury_ New treasury address
     */
    function setTreasury(address treasury_) external onlyRole(OPERATOR_ROLE) {
        require(treasury_ != address(0), "BridgeAxelar: zero address");
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    /**
     * @dev Send data to receiver in chainIdTo
     * 
     * @param data  data, which will be sent
     * @param receiver destination receiver address
     * @param chainIdTo  destination chain id 
     * @param destinationExecutor destination executor address
     * @param spentValue value which will be spent for axelar delivery
     * @param commission gas and eth value for destination execution
     */
    function send(
        bytes memory data,
        address receiver,
        uint64 chainIdTo,
        address destinationExecutor,
        uint256[][] memory spentValue,
        bytes[] memory commission
    ) public payable override onlyRole(GATEKEEPER_ROLE) returns (bool) {
        _send(data, receiver, chainIdTo, destinationExecutor, spentValue, commission);
    }

    /**
     * @dev Send data to receiver in chainIdTo
     * 
     * @param data  data, which will be sent
     * @param receiver destination receiver address
     * @param chainIdTo  destination chain id 
     * @param destinationExecutor destination executor address
     * @param spentValue value which will be spent for axelar delivery
     * @param commission gas and eth value for destination execution
     */
    function _send(
        bytes memory data,
        address receiver,
        uint64 chainIdTo,
        address destinationExecutor,
        uint256[][] memory spentValue,
        bytes[] memory commission
    ) internal returns (bool) {
        require(state == IBridgeV2.State.Active, "BridgeAxelar: state inactive");

        string memory chainId = networkById[chainIdTo];
        string memory destinationAddress = Strings.toHexString(uint160(receiver), 20);

        uint256 valuesLength = spentValue.length;
        uint256 valueAxelar = spentValue[valuesLength - 1][0];

        bytes memory sendData = abi.encode(data, destinationExecutor);

        INativeTreasury(treasury).getValue(valueAxelar);

        gasService.payNativeGasForContractCall{value: valueAxelar} (
            address(this),
            chainId,
            destinationAddress,
            sendData,
            treasury
        );

        gateway.callContract(
            chainId,
            destinationAddress,
            sendData
        );
    }
}

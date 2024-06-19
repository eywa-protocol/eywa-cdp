// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IBridgeV3.sol";

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { AxelarExpressExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/express/AxelarExpressExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';
import "@openzeppelin/contracts/utils/Strings.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/INativeTreasury.sol";

contract BridgeAxelar is AxelarExpressExecutable, IBridgeV3, AccessControlEnumerable, ReentrancyGuard {
// contract BridgeAxelar is AxelarExpressExecutable, IBridgeLZ, AccessControlEnumerable, ReentrancyGuard {
    
    using Address for address;
    
    /// @dev gate keeper role id
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev human readable version
    string public version;
    /// @dev current state Active\Inactive
    State public state;
    /// @dev nonces
    mapping(address => uint256) public nonces;

    /// @dev chainIdTo => dstEid
    mapping(uint256 => string) public networkById;
    IAxelarGasService public immutable gasService;
    address public treasury;


    event StateSet(State state);
    event TreasurySet(address treasury);

    // constructor(address gateway_, address gasService_) AxelarExpressExecutable(gateway_) {
    constructor(address gateway_, address gasService_) AxelarExpressExecutable(gateway_) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        version = "2.2.3";
        state = State.Active;

        gasService = IAxelarGasService(gasService_);
    }

    function setDstEids(uint256 chainIdTo_, string memory network) external {
        networkById[chainIdTo_] = network;
        // emit StateSet(state);
    }

    /**
     * @dev Set new state.
     *
     * Controlled by operator. Can be used to emergency pause send or send and receive data.
     *
     * @param state_ Active\Inactive state
     */
    function setState(State state_) external onlyRole(OPERATOR_ROLE) {
        state = state_;
        emit StateSet(state);
    }

    function setTreasury(address treasury_) external onlyRole(OPERATOR_ROLE) {
        require(treasury_ != address(0), "GateKeeper: zero address");
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function send(
        bytes32 data,
        address toSend,
        uint256 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) public payable override onlyRole(GATEKEEPER_ROLE) returns (bool) {
        _send(data, toSend, chainIdTo, toCall, valueToSpend, comissionLZ);
    }

    function _send(
        bytes32 data,
        address toSend,
        uint256 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) internal returns (bool) {
        require(state == State.Active, "Bridge: state inactive");

        string memory chainId = networkById[chainIdTo];
        string memory destinationAddress = Strings.toHexString(uint160(toSend), 20);

        uint256 valuesLength = valueToSpend.length;
        uint256 valueAxelar = valueToSpend[valuesLength - 1][0];

        bytes memory sendData = abi.encode(data, toCall);

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

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload_
    ) internal override {

        // TODO anyone can call it, make checks of sourceChain and source address
        require(state != State.Inactive, "Bridge: state inactive");
        (
            bytes32 data_, 
            address toCall_
        ) = abi.decode(payload_, (bytes32, address));
        IRouter(toCall_).saveReceivedHash(data_);
    }
}

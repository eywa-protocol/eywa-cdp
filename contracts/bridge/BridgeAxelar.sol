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
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeV2.sol";
import "../interfaces/IBridgeAxelar.sol";
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
    /// @dev chainIdTo => receiver
    mapping (uint64 => address) public receivers;
    /// @dev Axelar gas service
    IAxelarGasService public immutable gasService;
    /// @dev native treasury address
    address public treasury;

    event StateSet(IBridgeV2.State state);
    event TreasurySet(address treasury);
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
    function setDestinationNetwork(uint64 chainIdTo_, string memory network_) external {
        networkById[chainIdTo_] = network_;
        chainIds[network_] = chainIdTo_;
        emit NetworkSet(chainIdTo_, network_);
    }

    /**
     * @dev Set receiver for chainId
     * 
     * @param chainIdTo_ Chain ID of receiver
     */
    function setReceiver(uint64 chainIdTo_, address receiver_) external {
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
        uint256[][] memory spentValue,
        bytes[] memory comission
    ) public payable override onlyRole(GATEKEEPER_ROLE) returns (bool) {
        _send(params.data, uint64(params.chainIdTo), spentValue, comission);
    }

    /**
     * @dev Send data to receiver in chainIdTo
     * 
     * @param data  data, which will be sent
     * @param chainIdTo  destination chain id 
     * @param spentValue value which will be spent for axelar delivery
     * @param commission gas and eth value for destination execution
     */
    function _send(
        bytes memory data,
        uint64 chainIdTo,
        uint256[][] memory spentValue,
        bytes[] memory commission
    ) internal returns (bool) {
        require(state == IBridgeV2.State.Active, "BridgeAxelar: state inactive");

        string memory chainId = networkById[chainIdTo];
        string memory destinationAddress = Strings.toHexString(uint160(receivers[chainIdTo]), 20);

        uint256 valuesLength = spentValue.length;
        uint256 valueAxelar = spentValue[valuesLength - 1][0];

        INativeTreasury(treasury).getValue(valueAxelar);

        gasService.payNativeGasForContractCall{value: valueAxelar} (
            address(this),
            chainId,
            destinationAddress,
            data,
            treasury
        );

        gateway.callContract(
            chainId,
            destinationAddress,
            data
        );
    }

    receive() external payable {

    }
}

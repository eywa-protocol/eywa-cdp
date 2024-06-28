// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OAppSender, OAppCore, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeV2.sol";
import "../interfaces/IBridgeLZ.sol";
import "../interfaces/INativeTreasury.sol";


contract BridgeLZ is OAppSender, IBridgeV3, IBridgeLZ, AccessControlEnumerable, ReentrancyGuard {
    
    using Address for address;
    
    /// @dev gate keeper role id
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev treasury role id
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    /// @dev current state Active\Inactive
    IBridgeV2.State public state;
    /// @dev nonces
    mapping(address => uint256) public nonces;
    /// @dev chainIdTo => dstEid
    mapping(uint64 => uint32) public dstEids;
    /// @dev dstEid => chainIdTo
    mapping(uint32 => uint64) public chainIds;

    /// @dev native treasury address
    address public treasury;

    event StateSet(IBridgeV2.State state);
    event TreasurySet(address treasury);
    event DstEidSet(uint256 chainIdTo, uint32 dstEid);

    constructor(address _endpoint, address _owner) OAppCore(_endpoint, _owner) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        state = IBridgeV2.State.Active;
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
        require(treasury_ != address(0), "BridgeLZ: zero address");
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    /**
     * @dev Set dstEid for chainId
     * 
     * @param chainIdTo_ Chain ID to send
     * @param dstEid_ DstEid of chain
     */
    function setDstEids(uint64 chainIdTo_, uint32 dstEid_) external onlyRole(OPERATOR_ROLE) {
        require(chainIdTo_ != 0, "BridgeLZ: zero amount");
        require(dstEid_ != 0, "BridgeLZ: zero amount");
        dstEids[chainIdTo_] = dstEid_;
        chainIds[dstEid_] = chainIdTo_;
        emit DstEidSet(chainIdTo_, dstEid_);
    }

    // /**
    //  * @dev Send data to receiver in chainIdTo
    //  * 
    //  * Calls _send directrly or through treasury, if msg.value needed
    //  * 
    //  * @param data  data, which will be sent
    //  * @param chainIdTo  destination chain id 
    //  * @param spentValue value which will be spent for lz delivery
    //  * @param commissionLZ gas and eth value for destination execution
    //  */
    function sendV3(
        IBridgeV2.SendParams calldata params,
        address sender,
        uint256 nonce,
        uint256[][] memory spentValue,
        bytes[] memory comission
    ) public payable override onlyRole(GATEKEEPER_ROLE) returns (bool) {
        if (msg.value > 0) {
            _send(params.data, uint64(params.chainIdTo), spentValue, comission);
        } else {

            uint256 valuesLength = spentValue.length;
            uint256 valueLZ = spentValue[valuesLength - 1][1];

            INativeTreasury(treasury).callFromTreasury(
                valueLZ,
                params.data,
                uint64(params.chainIdTo),
                spentValue,
                comission
            );
        }
    }
    /**
     * @dev Call _send from treasury adress with msg.value
     * 
     * @param data data, which will be sent
     * @param chainIdTo destination chain id 
     * @param spentValue value which will be spent for lz delivery
     * @param commissionLZ gas and eth value for destination execution
     */
    function sendFromTreasury(
        bytes memory data,
        uint64 chainIdTo,
        uint256[][] memory spentValue,
        bytes[] memory commissionLZ
    ) public payable onlyRole(TREASURY_ROLE) returns (bool) {
        _send(data, chainIdTo, spentValue, commissionLZ);
    }

    /**
     * @dev Send data to receiver in chainIdTo
     * 
     * @param data  data, which will be sent
     * @param chainIdTo  destination chain id 
     * @param spentValue value which will be spent for lz delivery
     * @param commissionLZ gas and eth value for destination execution
     */
    function _send(
        bytes memory data,
        uint64 chainIdTo,
        uint256[][] memory spentValue,
        bytes[] memory commissionLZ
    ) internal returns (bool) {
        require(state == IBridgeV2.State.Active, "Bridge: state inactive");

        uint256 valuesLength = spentValue.length;
        uint256 valueLZ = spentValue[valuesLength - 1][1];

        bytes memory commission = commissionLZ[valuesLength - 1];

        _lzSend(
            dstEids[chainIdTo],
            data,
            commission,  
            MessagingFee(valueLZ, 0),
            treasury
        );
    }

    function quote(
        uint32 _dstEid,
        bytes memory _data,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        fee = _quote(_dstEid, _data, _options, _payInLzToken);
    }
}

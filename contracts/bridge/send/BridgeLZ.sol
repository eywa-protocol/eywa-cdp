// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2024 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OAppSender, OAppCore, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { IGateKeeper } from "../../interfaces/IGateKeeper.sol";
import "../../interfaces/IBridgeV3.sol";
import "../../interfaces/IBridgeV2.sol";
import "../../interfaces/INativeTreasury.sol";
contract BridgeLZ is OAppSender, IBridgeV3, AccessControlEnumerable, ReentrancyGuard {
    
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
    mapping(uint64 => uint32) public dstEids;

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
     * @dev Set dstEid for chainId
     * 
     * @param chainIdTo_ Chain ID to send
     * @param dstEid_ DstEid of chain
     */
    function setDstEid(uint64 chainIdTo_, uint32 dstEid_) external onlyRole(OPERATOR_ROLE) {
        require(chainIdTo_ != 0, "BridgeLZ: zero value");
        require(dstEid_ != 0, "BridgeLZ: zero value");
        dstEids[chainIdTo_] = dstEid_;
        emit DstEidSet(chainIdTo_, dstEid_);
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
        IBridgeV2.SendParams calldata params,
        address sender,
        uint256 nonce,
        bytes memory options
    ) public payable override onlyRole(GATEKEEPER_ROLE) {
        _send(params.data, uint64(params.chainIdTo), sender, options);
    }

    /**
     * @dev Send data to receiver in chainIdTo
     * 
     * @param data  data, which will be sent
     * @param chainIdTo  destination chain id 
     */
    function _send(
        bytes memory data,
        uint64 chainIdTo,
        address sender,
        bytes memory options
    ) internal returns (bool) {
        require(state == IBridgeV2.State.Active, "Bridge: state inactive");

        uint32 dstEid = dstEids[chainIdTo];
        MessagingFee memory gasFee = _quote(dstEid, data, options, false);
        _lzSend(
            dstEid,
            data,
            options,  
            gasFee,
            sender
        );
    }

    /**
     * @dev Quote price for LZ bride
     * 
     * @param _dstEid destination chain id
     * @param _data  data, which will be sent
     * @param _options additional data
     * @param _payInLzToken flag for chose token
     */
    function quote(
        uint32 _dstEid,
        bytes memory _data,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (uint256) {
        return _quote(_dstEid, _data, _options, _payInLzToken).nativeFee;
    }

    /**
     * @dev Quote price for LZ bridge
     * 
     * @param params send params
     * @param sender protocol which uses bridge
     * @param options additional call options
     */
    function estimateGasFee(
        IBridgeV2.SendParams calldata params,
        address sender,
        bytes memory options
    ) public view returns(uint256) {
        uint32 dstEid = dstEids[uint64(params.chainIdTo)];
        return _quote(dstEid, params.data, options, false).nativeFee;
    }

}

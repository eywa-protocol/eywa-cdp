// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IBridgeV3.sol";
import "./interfaces/IBridgeLZ.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/INativeTreasury.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

contract BridgeLZ is OApp, IBridgeV3, IBridgeLZ, AccessControlEnumerable, ReentrancyGuard {
    
    using Address for address;
    
    /// @dev gate keeper role id
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    /// @dev human readable version
    string public version;
    /// @dev current state Active\Inactive
    State public state;
    /// @dev nonces
    mapping(address => uint256) public nonces;

    /// @dev chainIdTo => dstEid
    mapping(uint256 => uint32) public dstEids;

    address public treasury;

    event StateSet(State state);
    event TreasurySet(address treasury);

    constructor(address _endpoint, address _owner) OApp(_endpoint, _owner) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        version = "2.2.3";
        state = State.Active;
    }

    function setPeer(uint32 _eid, bytes32 _peer) public override onlyOwner {
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
    function setState(State state_) external onlyRole(OPERATOR_ROLE) {
        state = state_;
        emit StateSet(state);
    }

    function setTreasury(address treasury_) external onlyRole(OPERATOR_ROLE) {
        require(treasury_ != address(0), "GateKeeper: zero address");
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function setDstEids(uint256 chainIdTo_, uint32 dstEid_) external onlyRole(OPERATOR_ROLE) {
        dstEids[chainIdTo_] = dstEid_;
        // emit StateSet(state);
    }

    function send(
        bytes32 data,
        address toSend,
        uint256 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) public payable override onlyRole(GATEKEEPER_ROLE) returns (bool) {
        if (msg.value > 0) {
            _send(data, toSend, chainIdTo, toCall, valueToSpend, comissionLZ);
        } else {

            uint256 valuesLength = valueToSpend.length;
            uint256 valueLZ = valueToSpend[valuesLength - 1][1];

            INativeTreasury(treasury).callFromTreasury(
                valueLZ,
                data,
                toSend,
                chainIdTo,
                toCall,
                valueToSpend,
                comissionLZ
            );
        }
    }

    function sendFromTreasury(
        bytes32 data,
        address toSend,
        uint256 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory comissionLZ
    ) public payable onlyRole(TREASURY_ROLE) returns (bool) {
        _send(data, toSend, chainIdTo, toCall, valueToSpend, comissionLZ);
    }

    function _send(
        bytes32 data,
        address toSend,
        uint256 chainIdTo,
        address toCall,
        uint256[][] memory valueToSpend,
        bytes[] memory commissionLZ
    ) internal returns (bool) {
        require(state == State.Active, "Bridge: state inactive");

        uint256 valuesLength = valueToSpend.length;
        uint256 valueLZ = valueToSpend[valuesLength - 1][1];

        bytes memory commission = commissionLZ[valuesLength - 1];

        bytes memory sendData = abi.encode(data, toCall);

        _lzSend(
            dstEids[chainIdTo],
            sendData,
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

    function _lzReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        address executor_,
        bytes calldata extraData_
    ) internal override {

        // TODO anyone can call it, make checks of source сhain and source address
        require(state != State.Inactive, "Bridge: state inactive");
        (
            bytes32 data_, 
            address toCall_
        ) = abi.decode(message_, (bytes32, address));
        IRouter(toCall_).saveReceivedHash(data_);
    }
}

// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2025 - all rights reserved

pragma solidity ^0.8.17;

import { ILayerZeroDVN } from "../../interfaces/ILayerZeroDVN.sol";
import { ISendLib } from "../../interfaces/ISendLib.sol";
import { IGateKeeper } from "../../interfaces/IGateKeeper.sol";
import { IChainIdAdapter } from "../../interfaces/IChainIdAdapter.sol";
import { IReceiveUln } from "../../interfaces/IReceiveUln.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract EywaDVN is ILayerZeroDVN, AccessControlEnumerable {
    
    /// @dev GateKeeper address
    address public gateKeeper;
    /// @dev ChainIdAdapter address
    address public chainIdAdapter;
    /// @dev operator role
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev receiver role
    bytes32 public constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");
    /// @dev sendlib role id
    bytes32 public constant SENDLIB_ROLE = keccak256("SENDLIB_ROLE");
    /// @dev defines max confirmation as LZ-DVN
    uint64 internal constant MAX_CONFIRMATIONS = type(uint64).max;
    /// @dev packet header size version(uint8) + nonce(uint64) + path(uint32,bytes32,uint32,bytes32)
    uint256 internal constant PACKET_HEADER_SIZE = 81;
    /// @dev list of DVNs on other chains
    mapping(uint64 => bytes32) public DVN;
    /// @dev receive lib address
    address public receiveLib;
    /// @dev options for send
    bytes[] public options;

    event BridgeSet(address);
    event ReceiverSet(uint64 chainId, bytes32 receiver);
    event ChainIdAdapterSet(address);
    event ReceiveLibSet(address);
    event OptionsSet(bytes[]);
    event FeesWithdrawn(address feeReceiver, uint256 feeAmount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * @dev Set GateKeeper address.
     * 
     * @param gateKeeper_ GateKeeper address
     */
    function setGateKeeper(address gateKeeper_) external onlyRole(OPERATOR_ROLE) {
        gateKeeper = gateKeeper_;
        emit BridgeSet(gateKeeper_);
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
     * @dev Set options for cross-chain call.
     * 
     * @param options_ additional options for bridges
     */
    function setOptions(bytes[] memory options_) external onlyRole(OPERATOR_ROLE) {
        options = options_;
        emit OptionsSet(options_);
    }

    /**
     * @dev Set DVN for chainId.
     * 
     * @param chainIds_ chain id
     * @param DVNs DVN address
     */
    function setDVNs(uint64[] memory chainIds_, bytes32[] memory DVNs) external onlyRole(OPERATOR_ROLE) {
        uint256 length = chainIds_.length;
        require(length == DVNs.length, "EywaDVN: wrong length");
        for (uint32 i; i < length; ++i) {
            DVN[chainIds_[i]] = DVNs[i];
            emit ReceiverSet(chainIds_[i], DVN[i]);
        }
    }

    /**
     * @dev Set receive library.
     * 
     * @param receiveLib_ address of receive library, where to call verify()
     */
    function setReceiveLib(address receiveLib_) external onlyRole(OPERATOR_ROLE) {
        require(receiveLib_ != address(0), "EywaDVN: zero address");
        receiveLib = receiveLib_;
        emit ReceiveLibSet(receiveLib_);
    }

    /**
     * @dev Assign job from LZ bridge.
     * 
     * @param param_ params of job
     * @param LZoptions_ additional options (not used)
     */
    function assignJob(AssignJobParam calldata param_, bytes calldata LZoptions_) external payable onlyRole(SENDLIB_ROLE) returns (uint256 fee) {
        (bytes memory data, bytes32 DVN_, uint64 chainIdTo) = _prepareCallData(param_.dstEid, param_.packetHeader, param_.payloadHash);
        return IGateKeeper(gateKeeper).sendData(
            data,
            DVN_,
            chainIdTo,
            options
        );
    }

    /**
     * @dev Estimate job from LZ bridge.
     * 
     * @param _dstEid dst eid
     * @param _confirmations count of confirmations (not used)
     * @param _sender sender address (not used)
     * @param _options additional options (not used)
     */
    function getFee(
        uint32 _dstEid,
        uint64 _confirmations,
        address _sender,
        bytes calldata _options
    ) external view returns (uint256 fee) {
        bytes memory packetHeader = new bytes(PACKET_HEADER_SIZE);
        bytes32 payloadHash;
        (bytes memory data, bytes32 DVN_, uint64 chainIdTo) = _prepareCallData(_dstEid, packetHeader, payloadHash);
         return IGateKeeper(gateKeeper).estimateGasFee(
            data,
            DVN_,
            chainIdTo,
            options
        );
    }

    /**
     * @dev Verify packet.
     * 
     * @param _packetHeader packet header
     * @param _payloadHash payload hash
     * @param _confirmations count of confirmations
     */
    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external onlyRole(RECEIVER_ROLE) {
        IReceiveUln(receiveLib).verify(_packetHeader, _payloadHash, _confirmations);
    }

    /**
     * @dev Withdraw fees from sendLib.
     * 
     * @param sendLib_ SendLib address
     * @param feeReceiver fee receiver address
     */
    function withdrawFeeLib(address sendLib_, address feeReceiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(feeReceiver != address(0), "EywaDVN: zero address");
        uint256 fee = ISendLib(sendLib_).fees(address(this));
        if (fee > 0) {
            ISendLib(sendLib_).withdrawFee(feeReceiver, fee);
            emit FeesWithdrawn(feeReceiver, fee);
        }
    }

    /**
     * @dev Validate sender and selector.
     * 
     * @param selector selector
     * @param from from address
     * @param chainIdFrom chain id from
     */
    function receiveValidatedData(bytes4 selector, address from, uint64 chainIdFrom) external onlyRole(RECEIVER_ROLE) returns (bool) {
        address DVN_ = address(uint160(uint256(DVN[chainIdFrom])));
        require(from == DVN_, "EywaDVN: wrong sender");
        require(selector == EywaDVN.verify.selector, "EywaDVN: wrong selector");
        return true;
    }

    function _prepareCallData(
        uint32 dstEid_, 
        bytes memory packetHeader, 
        bytes32 payloadHash
        ) internal view returns(bytes memory, bytes32, uint64) {
        uint64 chainIdTo = IChainIdAdapter(chainIdAdapter).dstEidToChainId(dstEid_);
        bytes memory data = abi.encodeWithSelector(
            ILayerZeroDVN.verify.selector, 
            packetHeader, 
            payloadHash, 
            MAX_CONFIRMATIONS
        );
        bytes32 DVN_ = DVN[chainIdTo];
        return (data, DVN_, chainIdTo);
    }
}

// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IReceiver.sol";
import "../interfaces/IGateKeeper.sol";
import "../utils/Block.sol";
import "../utils/Bls.sol";
import "../utils/Merkle.sol";
import "../utils/Typecast.sol";

contract BridgeV3 is IBridgeV3, AccessControlEnumerable, Typecast, ReentrancyGuard {
    
    using Address for address;
    using Bls for Bls.Epoch;

    /// @dev gate keeper role id
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");
    /// @dev validator role id
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev receiver that store thresholds
    address public receiver;
    /// @dev priceOracle that store prices for execution
    address public priceOracle;
    /// @dev human readable version
    string public version;
    /// @dev human readable tag
    string public tag;
    /// @dev current state Active\Inactive
    State public state;
    /// @dev received request IDs 
    mapping(uint32 epochNum => mapping(bytes32 => bool)) public requestIdChecker;
    // current epoch
    Bls.Epoch internal currentEpoch;
    // previous epoch
    Bls.Epoch internal previousEpoch;

    event EpochUpdated(bytes key, uint32 epochNum, uint64 protocolVersion);
    event RequestSent(
        bytes32 requestId,
        bytes data,
        address to,
        uint64 chainIdTo
    );
    event StateSet(State state);
    event ReceiverSet(address receiver);
    event PriceOracleSet(address priceOracle);
    event ValueWithdrawn(address to, uint256 amount);
    event GasPaid(bytes32 requestId, uint32 gasAmount);


    constructor(string memory tag_) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        version = "2.2.3";
        state = State.Inactive;
        tag = tag_;
    }

    /**
     * @dev Get current epoch.
     */
    function getCurrentEpoch() public view returns (bytes memory, uint8, uint32) {
        return (abi.encode(currentEpoch.publicKey), currentEpoch.participantsCount, currentEpoch.epochNum);
    }

    /**
     * @dev Get previous epoch.
     */
    function getPreviousEpoch() public view returns (bytes memory, uint8, uint32) {
        return (abi.encode(previousEpoch.publicKey), previousEpoch.participantsCount, previousEpoch.epochNum);
    }

    /**
     * @dev Updates current epoch.
     *
     * @param params ReceiveParams struct.
     */
    function updateEpoch(ReceiveParams calldata params) external onlyRole(VALIDATOR_ROLE) {
        // TODO ensure that new epoch really next one after previous (by hash)
        bytes memory payload = Merkle.prove(params.merkleProof, Block.txRootHash(params.blockHeader));
        (uint64 newEpochProtocolVersion, uint32 newEpochNum, bytes memory newKey, uint8 newParticipantsCount) = Block
            .decodeEpochUpdate(payload);

        require(currentEpoch.epochNum + 1 == newEpochNum, "Bridge: wrong epoch number");
    
        // TODO remove if when resetEpoch will be removed
        if (currentEpoch.isSet()) {
            verifyEpoch(currentEpoch, params);
            rotateEpoch();
        }

        // TODO ensure that new epoch really next one after previous (prev hash + params.blockHeader)
        bytes32 newHash = sha256(params.blockHeader);
        currentEpoch.update(newKey, newParticipantsCount, newEpochNum, newHash);

        onEpochStart(newEpochProtocolVersion);
    }

    /**
     * @dev Forcefully reset epoch on all chains.
     *
     * Controlled by operator. Should be removed at PoS stage.
     */
    function resetEpoch() public onlyRole(OPERATOR_ROLE) {
        // TODO consider to remove any possible manipulations from protocol
        if (currentEpoch.isSet()) {
            rotateEpoch();
            currentEpoch.epochNum = previousEpoch.epochNum + 1;
        } else {
            currentEpoch.epochNum = currentEpoch.epochNum + 1;
        }
        onEpochStart(0);
    }

    /**
     * @dev Send crosschain request v3.
     *
     * @param params struct with requestId, data, receiver and opposite cahinId
     * @param sender address to where send params
     * @param nonce unique nonce for send
     * @param options additional params for send
     */
    function sendV3(
        SendParams calldata params,
        address sender,
        uint256 nonce,
        bytes memory options
    ) external payable onlyRole(GATEKEEPER_ROLE) {
        require(state == State.Active, "Bridge: state inactive");
        require(previousEpoch.isSet() || currentEpoch.isSet(), "Bridge: epoch not set");

        address to = address(uint160(uint256(params.to)));

        emit RequestSent(
            params.requestId,
            params.data,
            to,
            params.chainIdTo
        );
        emit GasPaid(params.requestId, abi.decode(options, (uint32)));
    }

    /**
     * @dev Estimate crosschain request v3.
     *
     * @param params struct with requestId, data, receiver and opposite cahinId
     * @param sender address to where send params
     * @param options additional params for send
     */
    function estimateGasFee(
        SendParams calldata params,
        address sender,
        bytes memory options
    ) public view returns (uint256) {
        uint32 gasExecute = abi.decode(options, (uint32));
        (uint256 fee,) = IOracle(priceOracle).estimateFeeByChain(
            params.chainIdTo, 
            params.data.length, 
            gasExecute
        );
        return fee;
    }

    /**
     * @dev Withdraw value from this contract.
     *
     * @param value_ Amount of value
     */
    function withdrawValue(uint256 value_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success, ) = msg.sender.call{value: value_}("");
        require(success, "BridgeV3: failed to send Ether");
        emit ValueWithdrawn(msg.sender, value_);
    }

    /**
     * @dev Receive crosschain request v3.
     *
     * @param params array with ReceiveParams structs.
     */
    function receiveV3(ReceiveParams[] calldata params) external override onlyRole(VALIDATOR_ROLE) nonReentrant returns (bool) {
        
        require(state != State.Inactive, "Bridge: state inactive");

        for (uint256 i = 0; i < params.length; ++i) {
            bytes32 epochHash = Block.epochHash(params[i].blockHeader);

            // verify the block signature
            if (epochHash == currentEpoch.epochHash) {
                require(currentEpoch.isSet(), "Bridge: epoch not set");
                verifyEpoch(currentEpoch, params[i]);
            } else if (epochHash == previousEpoch.epochHash) {
                require(previousEpoch.isSet(), "Bridge: epoch not set");
                verifyEpoch(previousEpoch, params[i]);
            } else {
                revert("Bridge: wrong epoch");
            }

            // verify that the transaction is really in the block
            bytes memory payload = Merkle.prove(params[i].merkleProof, Block.txRootHash(params[i].blockHeader));

            // get call data
            (bytes32 requestId, bytes memory receivedData, address to, uint64 chainIdTo) = Block.decodeRequest(payload);
            require(chainIdTo == block.chainid, "Bridge: wrong chain id");

            bool isRequestIdReceived;
            if (epochHash == currentEpoch.epochHash) {
                isRequestIdReceived = requestIdChecker[currentEpoch.epochNum][requestId];
                requestIdChecker[currentEpoch.epochNum][requestId] = true;
            } else {
                isRequestIdReceived = requestIdChecker[previousEpoch.epochNum][requestId];
                requestIdChecker[previousEpoch.epochNum][requestId] = true;
            }

            if (!isRequestIdReceived) {
                uint256 length = receivedData.length - 1;
                payload = new bytes(length);
                for (uint i; i < length; ++i) {
                    payload[i] = receivedData[i];
                }
                if (receivedData[receivedData.length - 1] == 0x01){
                    require(payload.length == 128, "Bridge: Invalid message length");
                    (bytes32 payload_, bytes32 sender, uint256 chainIdFrom, ) = abi.decode(receivedData, (bytes32, bytes32, uint256, bytes32));
                    IReceiver(receiver).receiveHash(sender, uint64(chainIdFrom), payload_, requestId);
                } else if (receivedData[receivedData.length - 1] == 0x00) {
                    (bytes memory payload_, bytes32 sender, uint256 chainIdFrom, ) = abi.decode(receivedData, (bytes, bytes32, uint256, bytes32));
                    IReceiver(receiver).receiveData(sender, uint64(chainIdFrom), payload_, requestId);
                } else {
                    revert("Bridge: wrong message");
                }
            } else {
                revert("Bridge: request id already seen");
            }
        }
        return true;
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

    /**
     * @dev Set new receiver.
     *
     * Controlled by operator.
     *
     * @param receiver_ Receiver address
     */
    function setReceiver(address receiver_) external onlyRole(OPERATOR_ROLE) {
        require(receiver_ != address(0), "BridgeV3: zero address");
        receiver = receiver_;
        emit ReceiverSet(receiver_);
    }

    /**
     * @dev Set new price oracle.
     *
     * Controlled by operator.
     *
     * @param priceOracle_ GasPriceOracle address
     */
    function setPriceOracle(address priceOracle_) external onlyRole(OPERATOR_ROLE) {
        require(priceOracle_ != address(0), "BridgeV3: zero address");
        priceOracle = priceOracle_;
        emit PriceOracleSet(priceOracle_);
    }

    /**
     * @dev Verifies epoch.
     *
     * @param epoch current or previous epoch;
     * @param params oracle tx params
     */
    function verifyEpoch(Bls.Epoch storage epoch, ReceiveParams calldata params) internal view {
        Block.verify(
            epoch,
            params.blockHeader,
            params.votersPubKey,
            params.votersSignature,
            params.votersMask
        );
    }

    /**
     * @dev Moves current epoch and current request filter to previous.
     */
    function rotateEpoch() internal {
        previousEpoch = currentEpoch;
        Bls.Epoch memory epoch;
        currentEpoch = epoch;
    }

    /**
     * @dev Hook on start new epoch.
     */
    function onEpochStart(uint64 protocolVersion_) internal virtual {
        emit EpochUpdated(abi.encode(currentEpoch.publicKey), currentEpoch.epochNum, protocolVersion_);
    }
}

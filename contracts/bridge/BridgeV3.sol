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

    uint64 constant CHAIN_ID_ETHEREUM = 1;

    /// @dev nonce for senders
    mapping(address => uint256) public nonces;
    /// @dev receiver that store thresholds
    address public receiver;
    address public priceOracle;
    /// @dev human readable version
    string public version;
    /// @dev current state Active\Inactive
    State public state;
    /// @dev received request IDs 
    mapping(uint32 epochNum => mapping(bytes32 => bool)) public requestIdChecker;

    mapping(uint64 => ChainType) public chainTypes;

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

    event RequestSentV2(
        bytes32 requestId,
        bytes data,
        bytes32 to,
        uint64 chainIdTo
    );

    event StateSet(State state);
    event ReceiverSet(address receiver);
    event PriceOracleSet(address priceOracle);
    event ChainTypeSet(uint64 chainId, ChainType chainType);
    event ValueWithdrawn(address to, uint256 amount);
    event GasPaid(bytes32 requestId, uint32 gasAmount);


    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        version = "2.2.3";
        state = State.Inactive;
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
     */
    function sendV3(
        SendParams calldata params,
        address sender,
        uint256 nonce,
        bytes memory options
    ) external payable onlyRole(GATEKEEPER_ROLE) {
        require(state == State.Active, "Bridge: state inactive");
        require(previousEpoch.isSet() || currentEpoch.isSet(), "Bridge: epoch not set");
        require(nonce > nonces[sender], "Bridge: wrong nonce");
        nonces[sender] = nonce;

        address to = address(uint160(uint256(params.to)));

        emit RequestSent(
            params.requestId,
            params.data,
            to,
            params.chainIdTo
        );
        emit GasPaid(params.requestId, abi.decode(options, (uint32)));
    }

    function estimateGasFee(
        SendParams calldata params,
        address sender,
        bytes memory options
    ) public view returns (uint256) {
        ChainType chainType = chainTypes[params.chainIdTo];
        uint32 gasExecute = abi.decode(options, (uint32));
        if (chainType == ChainType.DEFAULT) {
            return _estimateGasFeeDefault(params.chainIdTo, gasExecute, params.data.length);
        } else if (chainType == ChainType.ARBITRUM) {
            return _estimateGasFeeArbitrum(params.chainIdTo, gasExecute, params.data.length);
        } else if (chainType == ChainType.OPTIMISM) {
            return  _estimateGasFeeOptimism(params.chainIdTo, gasExecute, params.data.length);
        }
    }

    function _estimateGasFeeDefault(uint64 chainIdTo, uint256 gasExecute, uint256 callDataBytesLength) internal view returns(uint256) {
        (uint256 gasCost, uint256 gasPerByte) = IOracle(priceOracle).getPrice(chainIdTo);
        return (gasExecute + callDataBytesLength * gasPerByte) * gasCost;
    }

    function _estimateGasFeeArbitrum(uint64 chainIdTo, uint256 gasExecute, uint256 callDataBytesLength) internal view returns(uint256) {
        (uint256 gasCost, uint256 gasPerByte) = IOracle(priceOracle).getPrice(chainIdTo);
        (uint256 gasPerL2Tx, uint256 gasPerL1CallData, uint256 arbitrumCompressionPercent) = IOracle(priceOracle).getPriceArbitrum();
        uint256 gasCallDataL1 = (callDataBytesLength * arbitrumCompressionPercent / 100 * gasPerL1CallData);
        return (gasExecute + gasPerL2Tx + gasCallDataL1 + callDataBytesLength * gasPerByte) * gasCost;

    }

    function _estimateGasFeeOptimism(uint64 chainIdTo, uint256 gasExecute, uint256 callDataBytesLength) internal view returns(uint256) {
        (uint256 gasCost, uint256 gasPerByte) = IOracle(priceOracle).getPrice(chainIdTo);
        (uint256 gasCostL1, uint256 gasPerByteL1) = IOracle(priceOracle).getPrice(CHAIN_ID_ETHEREUM);
        uint256 feeL1 = ((callDataBytesLength * gasPerByteL1) * gasCostL1);
        uint256 feeL2 = (gasExecute + callDataBytesLength * gasPerByte) * gasCost;
        return  feeL1 + feeL2;
    }

    function withdrawValue(uint256 value_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(value_);
        emit ValueWithdrawn(msg.sender, value_);
    }

    /**
     * @dev Receive (batch) crosschain request v2.
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
                    require(payload.length == 96, "Bridge: Invalid message length");
                    (bytes32 payload_, address sender, ) = abi.decode(receivedData, (bytes32, address, bytes32));
                    IReceiver(receiver).receiveHash(sender, payload_, requestId);
                } else if (receivedData[receivedData.length - 1] == 0x00) {
                    (bytes memory payload_, address sender, ) = abi.decode(receivedData, (bytes, address, bytes32));
                    IReceiver(receiver).receiveData(sender, payload_, requestId);
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
        require(receiver_ != address(0), "BridgeV2: zero address");
        receiver = receiver_;
        emit ReceiverSet(receiver_);
    }

    function setChainType(uint64[] memory chainIds_, ChainType[] memory chainTypes_) external onlyRole(OPERATOR_ROLE) {
        uint256 length = chainIds_.length;
        require(length == chainTypes_.length, "Bridge: wrong count");
        for (uint32 i; i < length; ++i) {
            chainTypes[chainIds_[i]] = chainTypes_[i];
            emit ChainTypeSet(chainIds_[i], chainTypes_[i]);
        }
    }

    function setPriceOracle(address priceOracle_) external onlyRole(OPERATOR_ROLE) {
        require(priceOracle_ != address(0), "BridgeV2: zero address");
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

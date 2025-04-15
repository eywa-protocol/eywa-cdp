// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/Typecast.sol";
import "../utils/RequestIdLib.sol";
import "../interfaces/IBridge.sol";
import "../interfaces/IGateKeeper.sol";
import "../interfaces/IAddressBook.sol";
import "../interfaces/IValidatedDataReciever.sol";
import { INativeTreasuryFactory } from '../interfaces/INativeTreasuryFactory.sol';
import { NativeTreasury } from '../bridge/NativeTreasury.sol';
import { INativeTreasury } from  "../interfaces/INativeTreasury.sol";


contract GateKeeper is IGateKeeper, AccessControlEnumerable, Typecast, ReentrancyGuard {
    using Address for address;

    struct BaseFee {
        /// @dev chainId The ID of the chain for which the base fee is being set
        uint64 chainId;
        /// @dev bridge 
        address bridge;
        /// @dev fee The amount of the base fee being set
        uint256 fee;
    }

    struct Rate {
        /// @dev chainId The ID of the chain for which the base fee is being set
        uint64 chainId;
        /// @dev bridge 
        address bridge;
        /// @dev rate The rate being set
        uint256 rate;
    }

    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev treasury admin role
    bytes32 public constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");
    /// @dev receiver conract
    address public receiver;
    /// @dev chainId => bridge => base fees
    mapping(uint64 => mapping(address => uint256)) public baseFees;
    /// @dev chainId => pay token => rate (per byte)
    mapping(uint64 => mapping(address => uint256)) public rates;
    /// @dev protocol => discounts, [0, 10000]
    mapping(address => uint256) public discounts;
    /// @dev nonce for senders
    mapping(address => uint256) public nonces;
    // @dev bridge => is registered
    mapping(address => bool) public registeredBridges;  
    // @dev protocol => treasury
    mapping(address => address) public treasuries; 
    // @dev array of sorted by priorities bridges. Bytes32 = protocol address + chainIdTo
    mapping(bytes32 => address[]) public bridgesByPriority;
    /// @dev protocol -> threshold
    mapping(bytes32 => uint8) public threshold;
    /// @dev msg.sender -> nonce -> hash of data
    mapping(address => mapping(uint256 => bytes32)) public sentDataHash;

    event ReceiverSet(address receiver);
    event BaseFeeSet(uint64 chainId, address bridge, uint256 fee);
    event RateSet(uint64 chainId, address bridge, uint256 rate);
    event DiscountSet(address protocol, uint256 discount);
    event FeesWithdrawn(address token, uint256 amount, address to);
    event ThresholdSet(address sender, uint64[] chainIds, uint8[] threshold);
    event BridgeRegistered(address bridge, bool status);
    event BridgesPriorityUpdated(address protocol, uint64[] chainIds, address[][] bridges);
    event DataSent(
        address[] selectedBridges, 
        bytes32 requestId, 
        bytes collectedData, 
        bytes32 to, 
        uint64 chainIdTo, 
        uint256 nonce, 
        address sender
    );
    event RetrySent(
        address bridge, 
        IBridge.SendParams params,
        uint256 nonce, 
        address sender
    );


    constructor(address receiver_) {
        require(receiver_ != address(0), "GateKeeper: zero address");
        receiver = receiver_;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    receive() external payable { }

    /**
     * @dev Sets the base fee for a given chain ID and token address.
     * The base fee represents the minimum amount of pay {TOKEN} required as transaction fee.
     *
     * @param baseFees_ The array of the BaseFee structs.
     */
    function setBaseFee(BaseFee[] memory baseFees_) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < baseFees_.length; ++i) {
            BaseFee memory baseFee = baseFees_[i];
            baseFees[baseFee.chainId][baseFee.bridge] = baseFee.fee;
            emit BaseFeeSet(baseFee.chainId, baseFee.bridge, baseFee.fee);
        }
    }

    /**
     * @notice Sets the address of the Receiver contract.
     *
     * @dev Only the contract admin is allowed to call this function.
     *
     * @param receiver_ the address of the new Receiver contract to be set.
     */
    function setReceiver(address receiver_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(receiver_ != address(0), "GateKeeper: zero address");
        receiver = receiver_;
        emit ReceiverSet(receiver_);
    }


    /**
     * @dev Register protocol, deploy trasury for it
     * 
     * @param treasuryAdmin_ admin of treasury, which can withdraw
     * @param protocol_ Protocol address who will use treasury
     */
    function registerProtocol(address treasuryAdmin_, address protocol_) external onlyRole(TREASURY_ADMIN_ROLE) {
        require(treasuries[protocol_] == address(0), "GateKeeper: protocol registered");
        address treasury = address(new NativeTreasury(treasuryAdmin_));
        treasuries[protocol_] = treasury;
    }

    /**
     * @dev Sets the rate for a given chain ID and token address.
     * The rate will be applied based on the length of the data being transmitted between the chains.
     *
     * @param rates_ The array of the Rate structs.
     */
    function setRate(Rate[] memory rates_) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < rates_.length; ++i) {
            Rate memory rate = rates_[i];
            rates[rate.chainId][rate.bridge] = rate.rate;
            emit RateSet(rate.chainId, rate.bridge, rate.rate);
        }
    }

    /**
     * @dev Sets the discount for a given protocol. Have to be in [0, 10000], where 10000 is 100%.
     *
     * @param protocol The address of the protocol for which the discount is being set;
     * @param discount The discount being set.
     */
    function setDiscount(address protocol, uint256 discount) external onlyRole(OPERATOR_ROLE) {
        require(discount <= 10000, "GateKeeper: wrong discount");
        discounts[protocol] = discount;
        emit DiscountSet(protocol, discount);
    }

    /**
     * @dev Calculates the cost for a cross-chain operation in the specified token.
     *
     * @param dataLength The length of the data being transmitted in the cross-chain operation;
     * @param chainIdTo The ID of the destination chain;
     * @param discountPersentage The discount for protocol;
     * @return amountToPay The fee amount to be paid for the cross-chain operation.
     */
    function calculateAdditionalFee(
        uint256 dataLength,
        uint64 chainIdTo,
        address bridge,
        uint256 discountPersentage
    ) public view returns (uint256 amountToPay) {
        uint256 baseFee = baseFees[chainIdTo][bridge];
        uint256 rate = rates[chainIdTo][bridge];
        require(baseFee != 0, "GateKeeper: base fee not set");
        require(rate != 0, "GateKeeper: rate not set");
        (amountToPay) = _getPercentValues(baseFee + (dataLength * rate), discountPersentage);
    }

    /**
     * @dev Retry transaction, that was send. Send it only with same params
     * 
     * @param params send params. params.data must be collectedData
     * @param nonce nonce
     * @param protocol protocol address
     * @param bridge bridge to retry send
     * @param currentOptions options of current call. Can be differ from first call
     * @param isHash flag for choose send data or hash
     */
    function retry(
        IBridge.SendParams memory params,
        uint256 nonce,
        address protocol,
        address bridge,
        bytes memory currentOptions,
        bool isHash
    ) external payable {
        require(registeredBridges[bridge], "GateKeeper: bridge not registered");
        require(sentDataHash[protocol][nonce] == keccak256(abi.encode(
            params,
            nonce,
            protocol
        )), "GateKeeper: wrong data");
        bool isBridgeFound;
        address[] memory protocolBridges = bridgesByPriority[_packKey(protocol, uint64(params.chainIdTo))];
        for (uint256 i; i < protocolBridges.length; ++i) {
            if (protocolBridges[i] == bridge) {
                isBridgeFound = true;
            }
        }
        require (isBridgeFound, "GateKeeper: wrong bridge");
        bytes32 requestId = RequestIdLib.prepareRequestId(
            params.to,
            params.chainIdTo,
            castToBytes32(protocol),
            block.chainid,
            nonce
        );
        if (isHash) {
            params.data = _encodeOut(abi.encode(keccak256(params.data), protocol, requestId), 0x01);
        } else {
            params.data = _encodeOut(abi.encode(params.data, protocol, requestId), 0x00);
        }

        (, uint256 gasFee) = _sendCustomBridge(
            bridge,
            params,
            nonce,
            protocol,
            currentOptions,
            discounts[address(0)]
        );
        
        require(msg.value >= gasFee, "GateKeeper: not enough value");
        (bool success, ) = treasuries[protocol].call{value: gasFee}("");
        require(success, "GateKeeper: failed to send Ether");
        if (msg.value > gasFee) {
            (success, ) = msg.sender.call{value: msg.value - gasFee}("");
            require(success, "GateKeeper: failed to send Ether");
        }
        emit RetrySent(bridge, params, nonce, msg.sender);
    }

    /**
     * @dev Allows the owner to withdraw collected fees from the contract. Use address(0) to
     * withdraw native asset.
     *
     * @param token The token address from which the fees need to be withdrawn;
     * @param amount The amount of fees to be withdrawn;
     * @param to The address where the fees will be transferred.
     */
    function withdrawFees(address token, uint256 amount, address to) external onlyRole(OPERATOR_ROLE) nonReentrant {
        if (token == address(0)) {
            (bool sent,) = to.call{value: amount}("");
            require(sent, "GateKeeper: failed to send Ether");
        } else {
            SafeERC20.safeTransfer(IERC20(token), to, amount);
        }
        emit FeesWithdrawn(token, amount, to);
    }

    /**
     * @dev Sets protocol's threshold. Must be the same on the receiver's side.
     *
     * @param protocol The protocol protocol contract address;
     * @param threshold_ The threshold for the given contract address.
     */
    function setThreshold(address protocol, uint64[] memory chainIdTo, uint8[] memory threshold_) external onlyRole(OPERATOR_ROLE) {
        uint256 length = chainIdTo.length;
        require(length == threshold_.length, "GateKeeper: wrong lengths");
        for (uint256 i; i < length; ++i) {
            require(threshold_[i] >= 1, "GateKeeper: wrong threshold");
            threshold[_packKey(protocol, chainIdTo[i])] = threshold_[i];
        }
        emit ThresholdSet(protocol, chainIdTo, threshold_);
    }

    /**
     * @dev Set bridge registration
     * 
     * @param bridge  bridge address
     * @param status  new status
     */
    function updateBridgeRegistration(address bridge, bool status) external onlyRole(OPERATOR_ROLE) {
        require(bridge != address(0), "GateKeeper: zero address");
        registeredBridges[bridge] = status;
        emit BridgeRegistered(bridge, status);
    }

    /**
     * @dev Updates bridge priority. 
     * 
     * @param protocol_ protocol address
     * @param chainIds_ List of chainIds for each pair protocol + chainId may be different bridge priority
     * @param bridges_ sorted by priority array for each chainId. First elem higher priority, then last
     */
    function updateBridgesPriority(address protocol_, uint64[] memory chainIds_, address[][] memory bridges_) external onlyRole(OPERATOR_ROLE) {
        uint256 length = chainIds_.length;
        require(length == bridges_.length, "GateKeeper: wrong lengths");
        for (uint256 i; i < length; ++i) {
            bridgesByPriority[_packKey(protocol_, chainIds_[i])] = bridges_[i];
        }
        emit BridgesPriorityUpdated(protocol_, chainIds_, bridges_);
    }

    /**
     * @dev Sends data to a destination contract
     *
     * @param data The data (encoded with selector) which would be send to the destination contract;
     * @param to The address of the destination contract;
     * @param chainIdTo The ID of the chain where the destination contract resides;
     * @param currentOptions Additional options for bridges. 
     *  Params must be sorted by priority
     *  bridge_1 - bridge with priority 1, bridge_2 - bridge with priority 2
     *  [bridge_1_options, bridge_2_options, bridge_3_options]
     */
    function sendData(
        bytes calldata data,
        bytes32 to,
        uint64 chainIdTo,
        bytes[] memory currentOptions
    ) external nonReentrant returns(uint256) {
         return _sendData(data, to, chainIdTo, currentOptions);
    }        

    /**
     * @dev Sends data to a destination contract
     */
    function _sendData(
        bytes calldata data,
        bytes32 to,
        uint64 chainIdTo,
        bytes[] memory currentOptions
    ) internal returns(uint256) {
        bytes memory out;
        bytes32 requestId;
        uint256 nonce;
        bytes memory collectedData;
        {
            (requestId, nonce, collectedData) = _buildData(to, chainIdTo, data);
            sentDataHash[msg.sender][nonce] = keccak256(abi.encode(
                IBridge.SendParams({
                        requestId: requestId,
                        data: collectedData,
                        to: to,
                        chainIdTo: chainIdTo
                }), 
                nonce,
                msg.sender
            ));
        }
        address[] memory selectedBridges = selectBridgesByPriority(msg.sender, chainIdTo);
        
        require(selectedBridges.length > 0, "GateKeeper: zero selected bridges");
        uint256 sendFee;
        for (uint8 i; i < selectedBridges.length; ++i) {
            if (i == 0) {
                out = _encodeOut(abi.encode(collectedData, msg.sender, requestId), 0x00); // isHash false
            } else if (i == 1) {
                out = _encodeOut(abi.encode(keccak256(collectedData), msg.sender, requestId), 0x01); // isHash true
            }
            (uint256 totalFee,) = _sendCustomBridge(
                selectedBridges[i], 
                IBridge.SendParams({
                        requestId: requestId,
                        data: out,
                        to: to,
                        chainIdTo: chainIdTo
                }), 
                nonce,
                msg.sender,
                currentOptions[i],
                discounts[msg.sender]
            );
            sendFee += totalFee;
        }
        emit DataSent(selectedBridges, requestId, collectedData, to, chainIdTo, nonce, msg.sender);
        return sendFee;
    }

    /**
     * @dev Select bridge by priority and by threshold
     * 
     * @param protocol protocol, which uses bridge
     * @param chainIdTo chain id to send
     */
    function selectBridgesByPriority(address protocol, uint64 chainIdTo) public view returns(address[] memory) {
        bytes32 key = _packKey(protocol, chainIdTo);
        uint8 threshold_ = threshold[key];
        require(threshold_ > 0, "GateKeeper: zero threshold");
        require(threshold_ <= bridgesByPriority[key].length, "GateKeeper: not enough bridges");
        address[] memory selectedBridges = new address[](threshold_);
        for (uint8 i; i < threshold_; ++i) {
            address currentBridge = bridgesByPriority[key][i];
            require(registeredBridges[currentBridge], "GateKeeper: bridge not registered");
            selectedBridges[i] = currentBridge;
        }
        return selectedBridges;
    }

    /**
     * @dev Returns the address of the part of the bridge that delivers to the destination chain.
     * In this case this is receiver contract
     * NOTE: to support legacy
     */
    function bridge() external view returns(address) {
        return receiver;
    }

    /**
     * @dev Sends data to a destination contract
     *
     * @param data The data (encoded with selector) which would be send to the destination contract;
     * @param to The address of the destination contract;
     * @param chainIdTo The ID of the chain where the destination contract resides;
     * @param currentOptions Additional options for bridges. 
     *  Params must be sorted by priority
     *  bridge_1 - bridge with priority 1, bridge_2 - bridge with priority 2
     *  [bridge_1_options, bridge_2_options, bridge_3_options]
     */
    function estimateGasFee(
        bytes calldata data,
        bytes32 to,
        uint64 chainIdTo,
        bytes[] memory currentOptions
    ) public view returns (uint256) {

        bytes32 requestId;
        uint256 nonce;
        bytes memory collectedData;
        (requestId, nonce, collectedData) = _buildData(to, chainIdTo, data);

        address[] memory selectedBridges = selectBridgesByPriority(msg.sender, uint64(chainIdTo));
        bytes memory out;
        uint256 totalFee;
        for (uint8 i; i < selectedBridges.length; ++i) {
            if (i == 0) {
                out = _encodeOut(abi.encode(collectedData, msg.sender, requestId), 0x00); // isHash false
            } else if (i == 1) {
                out = _encodeOut(abi.encode(keccak256(collectedData), msg.sender, requestId), 0x01); // isHash true
            }
            totalFee += _quoteCustomBridge(
                selectedBridges[i], 
                IBridge.SendParams({
                        requestId: requestId,
                        data: out,
                        to: to,
                        chainIdTo: chainIdTo
                }), 
                msg.sender,
                currentOptions[i],
                discounts[msg.sender]
            );
        }
        return totalFee;
    }

    /**
     * @dev Build data, requestId and nonce
     * 
     * @param to  address to send
     * @param chainIdTo chain id to send
     * @param data data to send
     */
    function _buildData(bytes32 to, uint64 chainIdTo, bytes calldata data) internal view returns(bytes32, uint256, bytes memory) {
        bytes32 requestId;
        uint256 nonce;
        bytes memory collectedData;
        {
            nonce = nonces[msg.sender] + 1;
            requestId = RequestIdLib.prepareRequestId(
                to,
                chainIdTo,
                castToBytes32(msg.sender),
                block.chainid,
                nonce
            );
            bytes memory info = abi.encodeWithSelector(
                IValidatedDataReciever.receiveValidatedData.selector,
                bytes4(data[:4]),
                castToBytes32(msg.sender),
                block.chainid
            );
            collectedData = abi.encode(
                data, 
                info, 
                nonce, 
                to
            );
        }
        return (requestId, nonce, collectedData);
    }

    /**
     * @dev Encode out data, add isHash bytes to end
     * 
     * @param out  out data
     * @param isHash is hash flag
     */
    function _encodeOut(bytes memory out, bytes1 isHash) internal pure returns(bytes memory newOut) {
        uint256 length = out.length;
        newOut = new bytes(length + 1);
        for (uint j; j < length; ++j) {
            newOut[j] = out[j];
        }
        newOut[length] = isHash;
    }

    /**
     * @dev Calculates the final amount to be paid after applying a discount percentage to the original amount.
     *
     * @param amount The original amount to be paid;
     * @param basePercent The percentage of discount to be applied;
     * @return amountToPay The final amount to be paid after the discount has been applied.
     */
    function _getPercentValues(
        uint256 amount,
        uint256 basePercent
    ) private pure returns (uint256 amountToPay) {
        require(amount >= 10, "GateKeeper: amount is too small");
        uint256 denominator = 10000;
        uint256 discount = (amount * basePercent) / denominator;
        amountToPay = amount - discount;
    }

    /**
     * @dev Send data by custom bridge
     * 
     * @param bridge_ bridge address
     * @param params params to send
     * @param nonce nonce 
     * @param protocol protocol address
     * @param options  additional options for bridge call
     */
    function _sendCustomBridge(
        address bridge_,
        IBridge.SendParams memory params,
        uint256 nonce,
        address protocol,
        bytes memory options,
        uint256 discountPersentage
    ) internal returns(uint256, uint256) {
        uint256 gasFee;
        uint256 totalFee;
        (totalFee, gasFee) = _calculateGasFee(
            bridge_,
            params,
            protocol,
            options,
            discountPersentage
        );
        INativeTreasury(treasuries[protocol]).getValue(totalFee);
        IBridge(bridge_).sendV3{value: gasFee}(
            params,
            protocol,
            nonce,
            options
        );
        return (totalFee, gasFee);
    }

    /**
     * @dev Quote fee for send
     * 
     * @param bridge_ bridge address
     * @param params params to send
     * @param protocol protocol address
     * @param options  additional options for bridge call
     * @param discountPersentage  discount persentage
     */
    function _quoteCustomBridge(
        address bridge_,
        IBridge.SendParams memory params,
        address protocol,
        bytes memory options,
        uint256 discountPersentage
    ) internal view returns (uint256) {
        (uint256 totalFee, ) = _calculateGasFee(
            bridge_,
            params,
            protocol,
            options,
            discountPersentage
        );
        return totalFee;
    }

    /**
     * @dev Calculate fees for send
     * 
     * @param bridge_ bridge address
     * @param params params to send
     * @param protocol protocol address
     * @param options  additional options for bridge call
     * @param discountPersentage  discount persentage
     */
    function _calculateGasFee(
        address bridge_,
        IBridge.SendParams memory params,
        address protocol,
        bytes memory options,
        uint256 discountPersentage
    ) internal view returns(uint256, uint256) {
        uint256 gasFee = IBridge(bridge_).estimateGasFee(
            params,
            protocol,
            options
        );
        uint256 additionalFee = calculateAdditionalFee(params.data.length, uint64(params.chainIdTo), bridge_, discountPersentage);
        uint256 totalFee = gasFee + additionalFee;
        return (totalFee, gasFee);
    }

    /**
     * @dev Pack address and uint64 to bytes32 as a key
     * 
     * @param addr  address
     * @param number number
     */
    function _packKey(address addr, uint64 number) internal pure returns(bytes32) {
        bytes32 packedKey = bytes32(uint256(uint160(addr)) << 64);
        packedKey |= bytes32(uint256(number));
        return packedKey;
    }
}

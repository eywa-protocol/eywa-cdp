// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/Typecast.sol";
import "../utils/RequestIdLib.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeV2.sol";
import "../interfaces/IGateKeeper.sol";
import "../interfaces/IAddressBook.sol";
import "../interfaces/IValidatedDataReciever.sol";
import { INativeTreasuryFactory } from '../interfaces/INativeTreasuryFactory.sol';
import { INativeTreasury } from  "../interfaces/INativeTreasury.sol";
contract GateKeeper is IGateKeeper, AccessControlEnumerable, Typecast, ReentrancyGuard {
    using Address for address;

    struct BaseFee {
        /// @dev chainId The ID of the chain for which the base fee is being set
        uint64 chainId;
        /// @dev payToken The token for which the base fee is being set; use 0x0 to set base fee in a native asset
        address payToken;
        /// @dev fee The amount of the base fee being set
        uint256 fee;
    }

    struct Rate {
        /// @dev chainId The ID of the chain for which the base fee is being set
        uint64 chainId;
        /// @dev payToken The token for which the base fee is being set; use 0x0 to set base fee in a native asset
        address payToken;
        /// @dev rate The rate being set
        uint256 rate;
    }

    /// @dev operator role id
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @dev chainId => pay token => base fees
    mapping(uint64 => mapping(address => uint256)) public baseFees;
    /// @dev chainId => pay token => rate (per byte)
    mapping(uint64 => mapping(address => uint256)) public rates;
    /// @dev caller => discounts, [0, 10000]
    mapping(address => uint256) public discounts;
    /// @dev nonce for senders
    mapping(address => uint256) public nonces;
    // @dev brdige => priority, 1 higher than 10, 0 priority turns off the bridge
    mapping(address => uint8) public bridgePriorities;  
    // @dev caller => treasury
    mapping(address => address) public treasuries; 
    // @dev rigistered bridges
    address[] public bridges;
    // @dev treasury factory
    address public treasuryFactory;
    /// @dev protocol -> threshold
    mapping(address => uint8) public threshold;
    /// @dev msg.sender -> nonce -> hash of data
    mapping(address => mapping(uint256 => bytes32)) public sendedData;

    event CrossChainCallPaid(address indexed sender, address indexed token, uint256 transactionCost);
    event BridgeSet(address bridge);
    event BaseFeeSet(uint64 chainId, address payToken, uint256 fee);
    event RateSet(uint64 chainId, address payToken, uint256 rate);
    event DiscountSet(address caller, uint256 discount);
    event FeesWithdrawn(address token, uint256 amount, address to);
    event TreasuryFactorySet(address treasury);
    event ThresholdSet(address sender, uint8 threshold);
    event BridgePrioritySet(address bridge, uint8 priority);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

    }

    function setTreasuryFactory(address treasuryFactory_) external onlyRole(OPERATOR_ROLE) {
        require(treasuryFactory_ != address(0), "GateKeeper: zero address");
        treasuryFactory = treasuryFactory_;
        emit TreasuryFactorySet(treasuryFactory_);
    }

    /**
     * @notice Sets the base fee for a given chain ID and token address.
     * The base fee represents the minimum amount of pay {TOKEN} required as transaction fee.
     * Use 0x0 as payToken address to set base fee in native asset.
     *
     * @param baseFees_ The array of the BaseFee structs.
     */
    function setBaseFee(BaseFee[] memory baseFees_) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < baseFees_.length; ++i) {
            BaseFee memory baseFee = baseFees_[i];
            baseFees[baseFee.chainId][baseFee.payToken] = baseFee.fee;
            emit BaseFeeSet(baseFee.chainId, baseFee.payToken, baseFee.fee);
        }
    }

    function registerCaller(address treasuryAdmin_, address caller_) external {
        require(treasuries[caller_] == address(0), "GateKeeper: caller registered");
        address treasury = INativeTreasuryFactory(treasuryFactory).createNativeTreasury(treasuryAdmin_);
        treasuries[caller_] = treasury;
    }

    /**
     * @notice Sets the rate for a given chain ID and token address.
     * The rate will be applied based on the length of the data being transmitted between the chains.
     *
     * @param rates_ The array of the Rate structs.
     */
    function setRate(Rate[] memory rates_) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < rates_.length; ++i) {
            Rate memory rate = rates_[i];
            rates[rate.chainId][rate.payToken] = rate.rate;
            emit RateSet(rate.chainId, rate.payToken, rate.rate);
        }
    }

    /**
     * @notice Sets the discount for a given caller. Have to be in [0, 10000], where 10000 is 100%.
     *
     * @param caller The address of the caller for which the discount is being set;
     * @param discount The discount being set.
     */
    function setDiscount(address caller, uint256 discount) external onlyRole(OPERATOR_ROLE) {
        require(discount <= 10000, "GateKeeper: wrong discount");
        discounts[caller] = discount;
        emit DiscountSet(caller, discount);
    }

    /**
     * @notice Calculates the cost for a cross-chain operation in the specified token.
     *
     * @param payToken The address of the token to be used for fee payment. Use address(0) to pay with Ether;
     * @param dataLength The length of the data being transmitted in the cross-chain operation;
     * @param chainIdTo The ID of the destination chain;
     * @param caller The address of the caller requesting the cross-chain operation;
     * @return amountToPay The fee amount to be paid for the cross-chain operation.
     */
    function calculateCost(
        address payToken,
        uint256 dataLength,
        uint64 chainIdTo,
        address caller
    ) public view returns (uint256 amountToPay) {
        uint256 baseFee = baseFees[chainIdTo][payToken];
        uint256 rate = rates[chainIdTo][payToken];
        require(baseFee != 0, "GateKeeper: base fee not set");
        require(rate != 0, "GateKeeper: rate not set");
        (amountToPay) = _getPercentValues(baseFee + (dataLength * rate), discounts[caller]);
    }

    function retry(
        IBridgeV2.SendParams memory params,
        uint256 nonce,
        address sender,
        address bridge,
        bytes memory currentOptions,
        bool isHash
        ) external payable {
        require(sendedData[sender][nonce] == keccak256(abi.encode(
            params,
            nonce,
            sender
        )), "GateKeeper: wrong data");

        if (isHash) {
            params.data = abi.encode(keccak256(params.data), isHash);
        } else {
            params.data = abi.encode(params.data, isHash);
        }

        uint256 gasFee = IBridgeV3(bridge).estimateGasFee(
            params,
            sender,
            currentOptions
        );
        IBridgeV3(bridge).sendV3{value: gasFee}(
            params,
            sender,
            nonce,
            currentOptions
        );
        if (msg.value > gasFee) {
            payable(msg.sender).transfer(msg.value - gasFee);
        }
    }

    /**
     * @notice Allows the owner to withdraw collected fees from the contract. Use address(0) to
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
     * @notice Sets caller's threshold. Must be the same on the receiver's side.
     *
     * @param caller The caller protocol contract address;
     * @param threshold_ The threshold for the given contract address.
     */
    function setThreshold(address caller, uint8 threshold_) external onlyRole(OPERATOR_ROLE) {
        require(threshold_ >= 1, "GateKeeper: wrong threshold");
        threshold[caller] = threshold_;
        emit ThresholdSet(caller, threshold_);
    }

    function registerBridge(address bridge, uint8 priority) external onlyRole(OPERATOR_ROLE) {
        require(bridge != address(0), "GateKeeper: zero address");
        uint256 bridgesLength = bridges.length;
        for (uint8 i; i < bridgesLength; ++i) {
            if (bridge == bridges[i]) {
                revert("GateKeeper: bridge registered");
            }
        }
        bridgePriorities[bridge] = priority;
        bridges.push(bridge);
    }

    // zero priority - bridge disabled
    function setBridgePriority(address bridge, uint8 priority) external onlyRole(OPERATOR_ROLE) {
        require(bridge != address(0), "GateKeeper: zero address");
        bridgePriorities[bridge] = priority;
        emit BridgePrioritySet(bridge, priority);
    }

    /**
     * @dev Sends data to a destination contract on a specified chain using the opposite BridgeV2 contract.
     * If payToken is address(0), the payment is made in Ether, otherwise it is made using the ERC20 token 
     * at the specified address.
     * The payment amount is calculated based on the data length and the specified chain ID and discount rate of the caller.
     *
     * Emits a PaymentReceived event after the payment has been processed.
     *
     * @param data The data (encoded with selector) which would be send to the destination contract;
     * @param to The address of the destination contract;
     * @param chainIdTo The ID of the chain where the destination contract resides;
     * @param options Additional options for bridges. 
     *  Params must be sorted by priority and from las to new chain
     *  bridge_1 - bridge with priority 1, bridge_2 - brdige with priority 2
     *  [ 
     *   [],
     *   ...
     *   [bridge_1_destination, bridge_2_destination, bridge_3_destination], 
     *   [bridge_1_hub, bridge_2_hub], 
     *   [bridge_1_source, bridge_2_source]  
     *  ]
     */
    function sendData(
        bytes calldata data,
        address to,
        uint64 chainIdTo,
        bytes memory options
    ) external nonReentrant {

        uint8 threshold_ = threshold[msg.sender];
        require(threshold_ > 0, "GateKeeper: zero threshold");
        address[] memory selectedBridges = _selectBridgesByPriority(threshold_);
        bytes memory out;
        bytes32 requestId;
        uint256 nonce;
        bytes memory collectedData;
        bytes[] memory currentOptions;
        {
            bytes[][] memory nextOptions;
            (currentOptions, nextOptions) = _popOptions(options);
            nonce = ++nonces[msg.sender];
            requestId = RequestIdLib.prepareRequestId(
                castToBytes32(to),
                chainIdTo,
                castToBytes32(msg.sender),
                block.chainid,
                nonce
            );
            bytes memory info = abi.encodeWithSelector(
                IValidatedDataReciever.receiveValidatedData.selector,
                bytes4(data[:4]),
                msg.sender,
                block.chainid
            );
            collectedData = abi.encode(
                abi.encode(data, nextOptions), 
                info, 
                nonce, 
                to
            );
            sendedData[msg.sender][nonce] = keccak256(abi.encode(
                IBridgeV2.SendParams({
                        requestId: requestId,
                        data: abi.encode(data, nextOptions),
                        to: to,
                        chainIdTo: chainIdTo
                }), 
                nonce,
                msg.sender
            ));
        }
        uint256 totalCost;
        for (uint8 i; i < selectedBridges.length; ++i) {
            if (i == 0) {
                bool isHash = false;
                out = abi.encode(collectedData, isHash);
            } else if (i == 1) {
                bool isHash = true;
                out = abi.encode(keccak256(collectedData), isHash);
            }

            totalCost += _sendCustomBridge(
                selectedBridges[i], 
                IBridgeV2.SendParams({
                        requestId: requestId,
                        data: out,
                        to: to,
                        chainIdTo: chainIdTo
                }), 
                nonce,
                msg.sender,
                currentOptions[i]
            );
        }
    }

    /**
     * @notice Calculates the final amount to be paid after applying a discount percentage to the original amount.
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

    function _selectBridgesByPriority(uint8 bridgeNumber) private view returns (address[] memory) {
        address[] memory selectedBridges = new address[](bridgeNumber);
        if (bridgeNumber == 0) return selectedBridges;
        address[] memory tempBridges = bridges;
        uint8 highestPriority = 255;
        uint8 highestPriorityIndex;
        uint256 tempBridgesLength = tempBridges.length;
        for (uint8 i; i < bridgeNumber; ++i) {
            for (uint8 j; j < tempBridgesLength; ++j) {
                if (bridgePriorities[tempBridges[j]] != 0 && highestPriority > bridgePriorities[tempBridges[j]]) {
                    highestPriority = bridgePriorities[tempBridges[j]];
                    highestPriorityIndex = j;
                }
            }
            selectedBridges[i] = tempBridges[highestPriorityIndex];
            highestPriority = 255;
            tempBridges[highestPriorityIndex] = address(0);
        }
        return selectedBridges;
    }

    function _sendCustomBridge(
        address bridge,
        IBridgeV2.SendParams memory params,
        uint256 nonce,
        address sender,
        bytes memory options
    ) internal returns(uint256) {
        uint256 gasFee = IBridgeV3(bridge).estimateGasFee(
            params,
            sender,
            options
        );
        INativeTreasury(treasuries[msg.sender]).getValue(gasFee);
        IBridgeV3(bridge).sendV3{value: gasFee}(
            params,
            sender,
            nonce,
            options
        );
        return gasFee;
    }

    function _popOptions(bytes memory options_) internal pure returns (bytes[] memory, bytes[][] memory) {
        bytes[][] memory options = abi.decode(options_,  (bytes[][]));
        bytes[] memory currentOptions = options[options.length - 1];

        bytes[][] memory nextOptions = new bytes[][](options.length - 1);
        
        for (uint8 i; i < options.length - 1; i++) {
            nextOptions[i] = options[i];
        }
        return (currentOptions, nextOptions);
    }

    receive() external payable {

    }
}

// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/Typecast.sol";
import "../utils/RequestIdLib.sol";
import "../interfaces/IBridgeV3.sol";
import "../interfaces/IBridgeV2.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IGateKeeper.sol";
import "../interfaces/IAddressBook.sol";
import "../interfaces/IValidatedDataReciever.sol";

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

    /// @dev bridge conract, can be changed any time
    address public bridgeEywa;
    /// @dev chainId => pay token => base fees
    mapping(uint64 => mapping(address => uint256)) public baseFees;
    /// @dev chainId => pay token => rate (per byte)
    mapping(uint64 => mapping(address => uint256)) public rates;
    /// @dev caller => discounts, [0, 10000]
    mapping(address => uint256) public discounts;

    // @dev brdige => priority, 1 higher than 10, 0 priority turns off the bridge
    mapping(address => uint8) public bridgePriorities;   
    // @dev rigistered bridges
    address[] public bridges;
    // @dev treasury for native value
    address public treasury;

    
    event CrossChainCallPaid(address indexed sender, address indexed token, uint256 transactionCost);
    event BridgeSet(address bridge);
    event BaseFeeSet(uint64 chainId, address payToken, uint256 fee);
    event RateSet(uint64 chainId, address payToken, uint256 rate);
    event DiscountSet(address caller, uint256 discount);
    event FeesWithdrawn(address token, uint256 amount, address to);
    event PrioritySet(address bridge, uint8 priority);
    event TreasurySet(address treasury);


    constructor(address bridgeEYWA_, address treasury_) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        require(bridgeEYWA_ != address(0), "GateKeeper: zero address");
        require(treasury_ != address(0), "GateKeeper: zero address");
        bridgeEywa = bridgeEYWA_;
        treasury = treasury_;
    }

    /**
     * @dev Returns same nonce as bridge (on request from same sender).
     */
    function getNonce() external view returns (uint256 nonce) {
        nonce = IBridgeV2(bridgeEywa).nonces(msg.sender);
    }

    /**
     * @notice Sets the address of the BridgeV2 contract.
     *
     * @dev Only the contract owner is allowed to call this function.
     *
     * @param bridge_ the address of the new BridgeV2 contract to be set.
     */
    function setBridge(address bridge_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bridge_ != address(0), "GateKeeper: zero address");
        bridgeEywa = bridge_;
        emit BridgeSet(bridgeEywa);
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
     * @param sender The address of the caller requesting the cross-chain operation;
     * @return amountToPay The fee amount to be paid for the cross-chain operation.
     */
    function calculateCost(
        address payToken,
        uint256 dataLength,
        uint64 chainIdTo,
        address sender
    ) public view returns (uint256 amountToPay) {
        uint256 baseFee = baseFees[chainIdTo][payToken];
        uint256 rate = rates[chainIdTo][payToken];
        require(baseFee != 0, "GateKeeper: base fee not set");
        require(rate != 0, "GateKeeper: rate not set");
        (amountToPay) = _getPercentValues(baseFee + (dataLength * rate), discounts[sender]);
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
        uint256 discount = (amount * basePercent) / 10000;
        amountToPay = amount - discount;
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

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    // if priority = 0, bridge disabled
    function setPriority(address bridge, uint8 priority) external onlyRole(OPERATOR_ROLE) {
        require(bridge != address(0), "GateKeeper: zero address");
        bridgePriorities[bridge] = priority;
        emit PrioritySet(bridge, priority);
    }

    function setTreasury(address treasury_) external onlyRole(OPERATOR_ROLE) {
        require(treasury_ != address(0), "GateKeeper: zero address");
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function registerBridge(address bridge, uint8 priority) external onlyRole(OPERATOR_ROLE) {
        require(bridge != address(0), "GateKeeper: zero address");
        require(bridgePriorities[bridge] == 0, "GateKeeper: bridge already registered");
        bridgePriorities[bridge] = priority;
        bridges.push(bridge);
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
        require(selectedBridges.length == bridgeNumber, "GateKeeper: not enough bridges");
        return selectedBridges;
    }

    /**
     * @dev Sends data to a destination contract on a specified chain using the opposite BridgeV2 contract.
     * If payToken is address(0), the payment is made in Ether, otherwise it is made using the ERC20 token 
     * at the specified address.
     * The payment amount is calculated based on the data length and the specified chain ID and discount rate of the sender.
     *
     * Emits a PaymentReceived event after the payment has been processed.
     *
     * @param data The data (encoded with selector) which would be send to the destination contract;
     * @param to The address of the destination contract;
     * @param chainIdTo The ID of the chain where the destination contract resides;
     * @param payToken The address of the ERC20 token used to pay the fee or address(0) if Ether is used.
     * @param bridgeNumber Number of bridges through which data will be transferred.
     * @param valuesToSpend  value [ [AxelarValueHUB, LZValueHUB], [AxelarValueSOURCE, LZValueSOURCE] ]
     * @param comissionLZ  comission [LZCommissionHUB, LZCommissionSOURCE]
     */
    function sendData(
        bytes calldata data,
        address to,
        uint64 chainIdTo,
        address payToken,
        uint8 bridgeNumber,
        uint256[][] memory valuesToSpend,
        bytes[] memory comissionLZ
    ) external payable nonReentrant {

        payable(treasury).transfer(msg.value);
        
        bytes32 dataHash;
        {
            uint256 amountToPayEywa = calculateCost(payToken, data.length, chainIdTo, msg.sender);
            _proceedCrosschainFees(payToken, amountToPayEywa, valuesToSpend);

            uint256 nonce = IBridgeV2(bridgeEywa).nonces(msg.sender);
            bytes32 requestId = RequestIdLib.prepareRequestId(
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
            bytes memory out = abi.encode(data, info, _popValues(valuesToSpend), _popCommissions(comissionLZ));

            IBridgeV2(bridgeEywa).sendV2(
                IBridgeV2.SendParams({
                    requestId: requestId,
                    data: out,
                    to: to,
                    chainIdTo: chainIdTo
                }),
                msg.sender,
                nonce
            );
            dataHash = keccak256(abi.encode(requestId, out, to, chainIdTo));
        }
        _sendHash(bridgeNumber, abi.encode(dataHash), chainIdTo, to, valuesToSpend, comissionLZ);
    }

    function _sendHash(
        uint8 bridgeNumber,
        bytes memory dataHash,
        uint64 chainIdTo,
        address toCall,
        uint256[][] memory valuesToSpend,
        bytes[] memory comissionLZ
    ) internal {
        address[] memory selectedBridges = _selectBridgesByPriority(bridgeNumber - 1);
        uint8 selectedBridgesLength = uint8(selectedBridges.length);

        // TODO what if msg.sender isn't router? P.S. It must be our router, because gateKeeper.sendData gives
        // access to HUB treasury
        address addressBook = IRouter(msg.sender).addressBook();
        for (uint8 i; i < selectedBridgesLength; ++i) {
            address sourceBridge = IAddressBook(addressBook).getDestinationBridge(selectedBridges[i], chainIdTo);
            IBridgeV3(selectedBridges[i]).send(
                dataHash,
                sourceBridge,
                chainIdTo,
                toCall,
                valuesToSpend,
                comissionLZ
            );
        }
    }

    function _popValues(uint256[][] memory values) internal pure returns(uint256[][] memory newValues) {
        uint256 valuesLength = values.length;
        if (valuesLength < 2) return newValues;
        newValues = new uint256[][](valuesLength - 1);
        for (uint8 i; i < valuesLength - 1; ++i) {
            newValues[i] = values[i];
        }
    }

    function _popCommissions(bytes[] memory commissions) internal pure returns(bytes[] memory newCommissions) {
        uint256 commissionsLength = commissions.length;
        if (commissionsLength < 2) return newCommissions;

        newCommissions = new bytes[](commissionsLength - 1);
        for (uint8 i; i < commissionsLength - 1; ++i) {
            newCommissions[i] = commissions[i];
        }
    }

    /**
     * @notice Proceeds with cross-chain fees payment in the specified token.
     *
     * @param payToken The address of the token to be used for fee payment.
     * @param transactionCostEywa The amount of fees to be paid for the cross-chain operation.
     * @param valuesToSpend Value that can spend each bridge.
     */
    function _proceedCrosschainFees(address payToken, uint256 transactionCostEywa, uint256[][] memory valuesToSpend) private {
        uint256 lastIndex = valuesToSpend.length - 1;
        uint256 transactionCostLZ = valuesToSpend[lastIndex][1];
        uint256 transactionCostAxelar = valuesToSpend[lastIndex][0];

        uint256 totalCost = transactionCostEywa + transactionCostLZ + transactionCostAxelar;
        emit CrossChainCallPaid(msg.sender, payToken, totalCost);
        if (payToken == address(0)) {
            require(msg.value >= totalCost, "GateKeeper: invalid payment amount");
        } else {
            SafeERC20.safeTransferFrom(IERC20(payToken), msg.sender, address(this), totalCost);
        }
    }

}

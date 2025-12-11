# EYWA Cross Chain Protocol  


[Overview](#overview)<br>
[Contracts](#contracts)
-   [GateKeeper](#contracts_GateKeeper)<br>

[Usage flow](#usage_flow)<br>


<a id="overview"></a>

## Overview
A protocol designed for cross-chain message transmission using multiple cross-chain bridges and consensus in a remote chain.

<a id="contracts"></a>

## Contracts

<a id="contracts_GateKeeper"></a>

### GateKeeper
The contract is the entry point for sending cross-chain messages. This contract configures the priority and threshold of bridges for a specific sender. Eywa, LayerZero, and Axelar bridges are currently used to send messages.

#### External Functions

----------

**setReceiver(address receiver)**

```solidity
function setReceiver(address receiver_) external;
```

-   **Description:**
    -   The function sets the address of the Receiver contract
    -   Available only for accounts with the DEFAULT_ADMIN_ROLE role
-   **Parameters:**
    -   `receiver_`: Receiver address


----------

**setBridgeEywa(address bridgeEywa)**

```solidity
function setBridgeEywa(address bridgeEywa_) external;
```

-   **Description:**
    -   The function sets the address of the BridgeEywa contract
    -   Available only for accounts with the DEFAULT_ADMIN_ROLE role
-   **Parameters:**
    -   `bridgeEywa_`: BridgeEywa address


----------

**setTreasury(address bridgeEywa)**

```solidity
function setTreasury(address treasury_) external;
```

-   **Description:**
    -   The function sets the address of the Treasury contract
    -   Available only for accounts with the DEFAULT_ADMIN_ROLE role
-   **Parameters:**
    -   `treasury_`: Treasury address


----------

**updateBridgeRegistration(address bridge, bool status)**

```solidity
function updateBridgeRegistration(address bridge, bool status) external;
```

-   **Description:**
    -   Function for configuring bridge status. If the bridge is not registered, it cannot be used to send cross-chain messages.
    -   Available only for accounts with the OPERATOR_ROLE role
-   **Parameters:**
    -   `bridge`: bridge address
    -   `status`: registration status


----------

**setBaseFee(BaseFee[] memory baseFees_)**

```solidity

struct BaseFee {
    uint64 chainId;
    address bridge;
    uint256 fee;
}

function setBaseFee(BaseFee[] memory baseFees_) external;

```

-   **Description:**
    -   Function to set the base fee for sending cross-chain messages for a specific bridge and target chain
    -   Available only for accounts with the OPERATOR_ROLE role
-   **Parameters:**
    -   `baseFees_`: Structure with base fee parameters, contains the following fields:
        -   `chainId`: target chain ID
        -   `bridge`: bridge address
        -   `fee`: fee amount

----------

**setRate(Rate[] memory rates_)**

```solidity

struct Rate {
    uint64 chainId;
    address bridge;
    uint256 fee;
}

function setBaseFee(Rate[] memory rates_) external;

```

-   **Description:**
    -   Function to set the rate for sending cross-chain messages for a specific bridge and target chain. The rate will be applied based on the length of the data being transmitted between the chains.
    -   Available only for accounts with the OPERATOR_ROLE role
-   **Parameters:**
    -   `rates_`: Structure with rate parameters, contains the following fields:
        -   `chainId`: target chain ID
        -   `bridge`: bridge address
        -   `fee`: fee amount

----------

**registerProtocol(Rate[] memory rates_)**

```solidity

function registerProtocol(address treasuryAdmin_, address protocol_) external;

```

-   **Description:**
    -   Function for registering a protocol. In order for a contract to use GateKeeper to send cross-chain messages, it must be registered. Such a registered contract is hereinafter referred to as a protocol. When registering a protocol, the NativeTreasury contract is deployed. This means that each registered protocol has its own NativeTreasury. Cross-chain messages are paid for from the balance of the corresponding NativeTreasury contract, so the protocol owner must replenish it in a timely manner.
    -   Available only for accounts with the TREASURY_ADMIN_ROLE role
-   **Parameters:**
    -   `treasuryAdmin_`: NativeTreasury administrator address — this account has the right to withdraw tokens from the NativeTreasury balance.
    -   `protocol_`: protocol address.

----------

**setThreshold(address protocol, uint64[] memory chainIdTo, uint8[] memory threshold_)**

```solidity

function setThreshold(
    address protocol,
    uint64[] memory chainIdTo,
    uint8[] memory threshold_
) external;

```

-   **Description:**
    -   Function for setting the threshold for the protocol for each specific network. The threshold value must be less than or equal to the number of bridges that are set to transmit messages for the protocol for the chain. For example, if the priority of bridges for the chain specifies bridges [**bridge_1**, **bridge_2**, **bridge_3**], then the threshold value must not exceed **3**. The threshold is the number of bridges used by default. In our example, if the threshold is set to **2**, then only bridges **bridge_1** and **bridge_2** are used to transmit messages by default. Bridge **bridge_3** can be used to resend the message using the **retry()** function.
    -   For successful message sending and receiving, the threshold value in the Receiver contract in the target chain must be set to the same or lower. 
    -   Available only for accounts with the OPERATOR_ROLE role
-   **Parameters:**
    -   `protocol`: Protocol address.
    -   `chainIdTo`: An array with chain IDs.
    -   `threshold_`: An array with threshold values for the corresponding chains.

----------

**updateBridgesPriority(address protocol_, uint64[] memory chainIds_, address[][] memory bridges_)**

```solidity

function updateBridgesPriority(
    address protocol_,
    uint64[] memory chainIds_,
    address[][] memory bridges_
) external;

```

-   **Description:**
    -   A function for setting the priority protocol for using bridges for specific chains. Each chain ID from chainIds_ corresponds to an array of addresses. Let's say you specified the array of addresses [**bridge_1**, **bridge_2**, **bridge_3**] for **chainId_1**. This means that when sending a message to **chainId_1** via the protocol, the bridges will be used in the order specified, i.e. **bridge_1**, then **bridge_2**, then **bridge_3**. In this case, the first bridge in the priority list always sends the message data, and all subsequent bridges send only the hash of this data.
    -   Available only for accounts with the OPERATOR_ROLE role
-   **Parameters:**
    -   `protocol`: Protocol address.
    -   `chainIds_`: An array with chain IDs.
    -   `bridges_`: An array of arrays of addresses, each element of `chainIds_` corresponds to an array of bridge addresses.

----------

**sendData(bytes data, bytes32 to, uint64 chainIdTo, bytes[] currentOptions)**

```solidity
function sendData(
    bytes calldata data,
    bytes32 to,
    uint64 chainIdTo,
    bytes[] memory currentOptions
) external returns(uint256 fee);
```

-   **Description:**
    -   The function sends cross-chain message using bridges in the priority specified for the sender who called this function.
-   **Parameters:**
    -   `data`: The encoded message.
    -   `to`: The message recipient address in bytes32 format.
    -   `chainIdTo`: The destination chain id.
    -   `currentOptions`: The options for bridges; must be sorted by priority:
        - If *bridge_1*, *bridge_2* and *bridge_3* are bridges with priority 1, 2 and 3 respectively, the options look like this:
        - [bridge_1_options, bridge_2_options, bridge_3_options, executor_options, external nonce\salt]

----------

**retry(SendParams params, uint256 nonce, address protocol, address bridge, bytes currentOptions, bool isHash)**

```solidity
function retry(
    IBridge.SendParams memory params,
    uint256 nonce,
    address protocol,
    address bridge,
    bytes memory currentOptions,
    bool isHash
) external payable;
```

-   **Description:**
    -   A function for resending a message if one of the bridges on the remote chain fails to work correctly.
-   **Parameters:**
    -   `params`: The message params.
    -   `nonce`: The nonce must match the nonce used in the first cross-chain message.
    -   `protocol`: The sender's address must match the sender in the cross-chain first message.
    -   `bridge`: The address of the bridge through which the cross-chain message will be resent.
    -   `currentOptions`: The options for the bridge
    -   `isHash`: The flag determines what needs to be sent - false - the message itself, true - the message hash

----------

**selectBridgesByPriority(address protocol, uint64 chainIdTo)**

```solidity
function selectBridgesByPriority(
    address protocol,
    uint64 chainIdTo
) public view returns(address[] memory);
```

-   **Description:**
    -   The function returns a list of bridges by priority for a specific message sender and destination chain..
-   **Parameters:**
    -   `protocol`: The message sender address.
    -   `chainIdTo`: The destination chain ID.


----------

**estimateGasFee(bytes data, bytes32 to, uint64 chainIdTo, bytes[] currentOptions)**

```solidity
function estimateGasFee(
    bytes calldata data,
    bytes32 to,
    uint64 chainIdTo,
    bytes[] memory currentOptions
) external returns(uint256 fee);
```

-   **Description:**
    -   Function for calculating the commission fee for sending a cross-chain message.
-   **Parameters:**
    -   `data`: The encoded message.
    -   `to`: The message recipient address in bytes32 format.
    -   `chainIdTo`: The destination chain id.
    -   `currentOptions`: The options for bridges; must be sorted by priority:
        - If *bridge_1*, *bridge_2* and *bridge_3* are bridges with priority 1, 2 and 3 respectively, the options look like this:
        - [bridge_1_options, bridge_2_options, bridge_3_options, executor_options, external nonce\salt]

----------

<a id="usage_flow"></a>

## Usage flow

To send a cross-chain message, you must correctly form the arguments for the **sendData()** function

1. The data argument must contain **calldata** to call the function on the target contract, in the standard **Solidity** format

For example, if you want to call the function **someFuntion(uint256 arg1, uint256 arg2)**, then you can create **calldata** using the **ethers** library

```js
const { ethers } = require("ethers");

const arg1 = 1;
const arg2 = 2;

const abi = ["function someFuntion(uint256 arg1, uint256 arg2) external"];

const iface = new ethers.utils.Interface(abi);

const data = iface.encodeFunctionData("someFuntion", [arg1, arg2]);

```

2. The argument **to** must contain an address in bytes32 format; this is necessary for compatibility with non-EVM blockchains.

```js
const { ethers } = require("ethers");

const targetAddress = "0x...";
const targetAddressBytes32 = ethers.utils.hexZeroPad(targetAddress, 32);

```

3. The **chainIdTo** argument must contain the numerical value of the chain.

```js
const chainIdTo = 1;

```

4. The **currentOptions** argument must contain encoded options for bridges, which contain information about the gas limit for delivering the transmitted data, the commission for executing the function called on the target contract, and a nonce that is unique for each cross-chain message of this protocol.

The array of options generally looks like this:

[**options_for_bridges_1**, **options_for_bridges_2**, **options_for_bridges_3**, **options_for_execute**, **encode_nonce**]


Example of generating options for bridges


```js
const { Options } = require('@layerzerolabs/lz-v2-utilities');
const { ethers } = require("ethers");
const abi = ethers.utils.defaultAbiCoder;

// options for the Eywa bridge
const gasLimitEywa = /*gas limit*/;
const optionsEywa = abi.encode(["uint32"], [gasLimitEywa]);

// options for the Layer Zero bridge
const gasLimitLZ = /*gas limit*/;
const optionsLZ = Options.newOptions().addExecutorLzReceiveOption(gasLimitLZ, 0).toHex();

// options for the Axelar bridge
const gasLimitAxelar = /*gas limit*/;
const optionsAxelar = abi.encode(["uint256", "bytes"], [gasLimitAxelar, "0x"]);

// payment options for performing a target function in a target chain
const feeForExecute = /*fee for execute*/;
const payForExecuteOptions = abi.encode(["uint32"], [feeForExecute]);

// The nonce must be unique for each new cross-chain message sent from the protocol.
const nonce = /*uniq nonce*/;
const nonceEncode = abi.encode(["uint256"], [nonce]);

// option encoding
const bridgeOptions = [optionsEywa, optionsLZ, optionsAxelar, payForExecuteOptions, nonceEncode];
const currentOptions = abi.encode(["bytes[]"], [bridgeOptions]);

```

For more information on creating options for Axelar and Layer Zero bridges, please refer to their documentation.

Important!

If the priority of bridges in the direction of a specific chain 

[**bridges_1**, **bridges_2**, **bridges_3**]

The options should be arranged in the same order:

[**options_for_bridges_1**, **options_for_bridges_2**, **options_for_bridges_3**, **options_for_execute**, **encode_nonce**]

Also, the number of options for bridges must match the threshold.
If you have **3** bridges in your priority list, but the threshold is **2**, this means that by default the message is sent by **2** bridges, and the **3rd** bridge can be used to resend the message, and the options should look like this

[**options_for_bridges_1**, **options_for_bridges_2**, **options_for_execute**, **encode_nonce**]


If one of the bridges in the remote chain fails, you can resend the message using one of the bridges specified in the priority. If you have **2** out of **3**, then bridge **3** is used for this purpose.

To resend a cross-chain message, you need to correctly form the arguments for the **retry()** function

1. The **params** argument contains a structure with data

```js
const { ethers } = require('hardhat');
const { hexZeroPad } = ethers.utils;
const abi = ethers.utils.defaultAbiCoder;

// request id of the previously sent message
const requestId = /*requestId*/;
// previously sent data
const sendedData = "0x...";
// id of the current chain
const chainIdCurrent = /*chainIdCurrent*/;
// id of the target chain
const chainIdTo = /*const*/;
// protocol address
const protocol = "0x...";
// destination address in the remote network in bytes32
const targetBytes32 = "0x...";
// nonce used when sending a message
const nonce = /*nonce*/;

const receiveValidatedDataSelector = "0x2509db2b";
const sendDataSelector = sendedData.slice(0, 10);

const info = receiveValidatedDataSelector + abi.encode(
    ["bytes4", "bytes32", "uint256"],
    [sendDataSelector, hexZeroPad(protocol.address, 32), chainIdCurrent]
).slice(2);
const collectedData = abi.encode(["bytes", "bytes", "uint256", "bytes32"], [sendedData, info, nonce, targetBytes32]);

const params = {
    requestId: requestId,
    data: collectedData,
    to: targetBytes32,
    chainIdTo: chainIdTo
}

```

2. The **nonce** argument must match the **nonce** that was used when the message was first sent.

3. The **protocol** - is protocol address.

4. The **bridge** argument is the address of the bridge to which you want to forward the message.

5. The **currentOptions** argument specifies the options for the specific bridge through which the message is being forwarded.

6. The **isHash** argument determines what you want to forward: **true** - only the message hash is sent, **false** - the entire message is sent. Its use depends on what exactly you did not receive in the remote network - the message itself or its hash.


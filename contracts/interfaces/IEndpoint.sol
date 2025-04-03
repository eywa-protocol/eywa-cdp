// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IEndpoint {

    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct SetConfigParam {
        uint32 eid;
        uint32 configType;
        bytes config;
    }

    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory);

    function setConfig(address _oapp, address _lib, SetConfigParam[] calldata _params) external;
}





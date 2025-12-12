// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ISendLib {

    function withdrawFee(address _to, uint256 _amount) external;

    function fees(address feeReceiver) external returns(uint256);
}

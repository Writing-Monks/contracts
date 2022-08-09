// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

interface ITweetRequester {

    /** 
    /* @notice ensure that this function can only be called by the Twitter Consumer. Also, note that this function needs to use less than 400000 gas.
    */
    function receiveTweetInfo(bytes32 requestId_, uint value_) external;
}
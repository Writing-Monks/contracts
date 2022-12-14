// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.17;

interface ITweetRelayerClient {
    /** 
    /* @notice ensure that these functions can only be called by the Twitter Relayer. Also, note that these function needs to use less than 400000 gas.
    */
    function onTweetInfoReceived(bytes32 requestId_, uint value_) external;
    function onTweetPosted(bytes32 requestId_, uint createdAt_, uint tweetId_) external;
}
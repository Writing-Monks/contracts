pragma solidity ^0.8.15;

import "../../src/oracle/ITweetRelayerClient.sol";


contract MockTweetRelayerClient is ITweetRelayerClient {
    bytes32 public requestId;
    uint public value;
    uint public value2;

    function onTweetInfoReceived(bytes32 requestId_, uint value_) public {
        requestId = requestId_;
        value = value_;
    }

    function onTweetPosted(bytes32 requestId_, uint createdAt_, uint tweetId_) public{
        requestId = requestId_;
        value = createdAt_;
        value2 = tweetId_;
    }
}
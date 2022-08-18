//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/oracle/ITweetRelayerClient.sol";
import "../../src/oracle/ITweetRelayer.sol";


contract MockTweetRelayerClient is ITweetRelayerClient {
    bytes32 public requestId;
    uint public value;
    uint public value2;

    ITweetRelayer private immutable _tweetRelayer;

    constructor(address tweetRelayer_) {
        _tweetRelayer = ITweetRelayer(tweetRelayer_);
    }

    function onTweetInfoReceived(bytes32 requestId_, uint value_) public {
        requestId = requestId_;
        value = value_;
    }

    function onTweetPosted(bytes32 requestId_, uint createdAt_, uint tweetId_) public{
        requestId = requestId_;
        value = createdAt_;
        value2 = tweetId_;
    }

    function requestLikeCount(uint tweetId) public {
        requestId = _tweetRelayer.requestTweetLikeCount(tweetId);
    }

    function requestTweetPublication(bytes20 postId) public {
        requestId = _tweetRelayer.requestTweetPublication(postId);
    }
}
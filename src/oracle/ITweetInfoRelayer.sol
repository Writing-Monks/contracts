// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

interface ITweetInfoRelayer {

    function requestTweetLikeCount(uint tweetId_) external returns (bytes32 requestId);
    function requestTweetCreationTimestamp(uint tweetId_) external returns (bytes32 requestId);
}
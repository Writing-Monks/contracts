// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

interface ITweetRelayer {

    function requestTweetData(string memory tweetId_, string memory fields_, string memory path_) external returns (bytes32 requestId);
    function requestTweetLikeCount(uint tweetId_) external returns (bytes32 requestId);
    function requestTweetPublication(bytes20 postId_) external returns (bytes32 requestId);
}
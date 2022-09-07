// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.16;

interface ITweetRelayer {
    function requestTweetData(string memory tweetId_, string memory fields_, string memory path_) external returns (bytes32 requestId);
    function requestTweetLikeCount(uint tweetId_) external returns (bytes32 requestId);
    function requestTweetPublication(bytes20 postId_) external returns (bytes32 requestId);
}
// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

import "../core/MonksTypes.sol";
import "./IMonksPublication.sol";

interface IMonksMarket {
    function init(bytes20 postId_, MonksTypes.Post memory post_) external;
    function author() external view returns (address);
    function publish() external;
    function setPublishTimeAndTweetId(uint createdAt_, uint tweetId_) external;

    function resolve(uint result_) external;
    function tweetId() external returns (uint);
    function publishTime() external returns (uint);
    function funding() external returns (uint);
    function payoutSplitBps() external returns (MonksTypes.PayoutSplitBps memory);

    function buy(int sharesToBuy_, bool isYes_, uint maximumCost_) external;
    function deltaPrice(int shares, bool isYes) external view returns (uint);
}
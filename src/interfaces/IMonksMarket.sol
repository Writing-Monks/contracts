// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "../core/MonksTypes.sol";
import "./IMonksPublication.sol";

error MarketExceededMaxCost();
error InvalidMarketStatusForAction();

interface IMonksMarket {
    enum Status {Active, Expired, Flagged, Deleted, Published, Resolved}

    function init(bytes20 postId_, MonksTypes.Post memory post_) external;
    function postTypeAndAuthor() external view returns (uint8, address);
    function publish() external;
    function setPublishTimeAndTweetId(uint createdAt_, uint tweetId_) external;
    function status() external view returns (Status);

    function resolve(uint result_) external;
    function tweetId() external returns (uint);
    function publishTime() external returns (uint);
    function funding() external returns (uint);
    function payoutSplitBps() external returns (MonksTypes.PayoutSplitBps memory);

    function buy(int sharesToBuy_, bool isYes_, uint amountToPay_, address buyer_) external;
    function deltaPrice(int shares, bool isYes) external view returns (uint);
}
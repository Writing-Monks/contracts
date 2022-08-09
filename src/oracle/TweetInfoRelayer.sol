// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./ITweetRequester.sol";

error UnableToTransfer();
error NotEnoughLink();


contract TweetInfoRelayer is ChainlinkClient {
    using Chainlink for Chainlink.Request;
    using Strings for uint;

    mapping(address => uint) public linkBalance;

    mapping(bytes32 => address) private _requesters;
    
    bytes32 immutable private jobId;
    uint256 immutable private fee;

    constructor(address linkAddress_, address oracleAddress_) {
        setChainlinkToken(linkAddress_);
        setChainlinkOracle(oracleAddress_);
        jobId = 'ca98366cc7314957b8c012c72f05aeeb';
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0.1 * 10**18
    }

    /**
     * Makes a call to the twitter api endpoint: https://api.twitter.com/2/tweets/:tweetId
     * you can add params on tweet.field.
     * The output of the twitter api looks like this:
     * {'data':
         {'id': '1547210281406943232',
          'public_metrics': {'retweet_count': 237, 'reply_count': 342, 'like_count': 3941, 'quote_count': 59},
          'text': 'This is the tweet'
         }
       }
     * Especify the path to your result on the path variable, ignoring the data keyword. Example, to obtain the like_count, path should be 'public_metrics,like_count'
     
     * Twitter outputs an isostring for the created_at (e.g. "created_at": "2022-07-13T13:24:11.000Z"), we translate this to a timestamp to get an uint.
     */
    function requestTweetData(string memory tweetId_, string memory fields_, string memory path_) public returns (bytes32 requestId) {
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        if (linkBalance[msg.sender] < fee) {
            revert NotEnoughLink();
        }
        linkBalance[msg.sender] -= fee;

        req.add('tweetId', tweetId_);
        req.add('tweet.fields', fields_);
        req.add('path', path_);
        
        requestId = sendChainlinkRequest(req, fee);
        _requesters[requestId] = msg.sender;
    }

    /**
    * @dev some prebuilt calls for the most common requests.
    */
    function requestTweetLikeCount(uint tweetId_) public returns (bytes32 requestId) {
        return requestTweetData(tweetId_.toString(), 'public_metrics', 'public_metrics,like_count');
    }

    function requestTweetCreationTimestamp(uint tweetId_) public returns (bytes32 requestId) {
        return requestTweetData(tweetId_.toString(), 'created_at', 'created_at');
    }

    /**
    * @notice spends at max 400000 gas when calling the receiver.
    */
    function fulfill(bytes32 requestId_, uint256 value_) public recordChainlinkFulfillment(requestId_) {
        ITweetRequester requester = ITweetRequester(_requesters[requestId_]);
        requester.receiveTweetInfo{gas: 400000}(requestId_, value_);
    }

    function depositLink(uint amount_, address to_) public {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        if (!link.transferFrom(msg.sender, address(this), amount_)) {
            revert UnableToTransfer();
        }
        linkBalance[to_] += amount_;
    }

    function withdraw() public {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        uint amount = linkBalance[msg.sender];
        linkBalance[msg.sender] = 0;
        if (!link.transfer(msg.sender, amount)){
            revert UnableToTransfer();
        }
    }
}
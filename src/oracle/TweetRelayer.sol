// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./ITweetRelayer.sol";
import "./ITweetRelayerClient.sol";

error UnableToTransfer();
error NotEnoughLink();


/*
 * @note This contract interfaces with the oracle to post tweets and read info from tweet (e.g. like counts)
*/
contract TweetRelayer is ITweetRelayer, ChainlinkClient {
    using Chainlink for Chainlink.Request;
    using Strings for uint;

    mapping(address => uint) public linkBalance;

    mapping(bytes32 => address) private _requesters;
    
    bytes32 public readTweetJobId;
    bytes32 public writeTweetJobId;
    uint256 constant private fee = (1 * LINK_DIVISIBILITY) / 10; // 0.1 * 10**18

    constructor(address linkAddress_, address operatorAddress_, bytes32 readTweetJobId_, bytes32 writeTweetJobId_) {
        setChainlinkToken(linkAddress_);
        setChainlinkOracle(operatorAddress_);
        readTweetJobId = readTweetJobId_;
        writeTweetJobId = writeTweetJobId_;
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
     * Specify the path to your result on the `path` variable, ignoring the data keyword. Example, to obtain the like_count, path should be 'public_metrics,like_count'
     
     * Twitter outputs an isostring for the created_at field (e.g. "created_at": "2022-07-13T13:24:11.000Z"), we translate this to a timestamp to get an uint.
     */
    function requestTweetData(string memory tweetId_, string memory fields_, string memory path_) public returns (bytes32 requestId) {
        _chargeLink();

        Chainlink.Request memory req = buildOperatorRequest(readTweetJobId, this.fulfillInfo.selector);
        req.add('tweetId', tweetId_);
        req.add('tweet_fields', fields_);
        req.add('path', path_);
        
        requestId = sendOperatorRequest(req, fee);
        _requesters[requestId] = msg.sender;
    }

    function requestTweetPublication(bytes20 postId_, bytes20 adId_) public returns (bytes32 requestId) {
        _chargeLink();

        Chainlink.Request memory req = buildOperatorRequest(writeTweetJobId, this.fulfillPublication.selector);
        req.add('pub', toAsciiString(msg.sender));
        req.add('postId', string(abi.encodePacked(postId_)));
        req.add('adId', string(abi.encodePacked(adId_)));

        requestId = sendOperatorRequest(req, fee);
        _requesters[requestId] = msg.sender;
    }

    /**
    * @dev a prebuilt call to get the like count.
    */
    function requestTweetLikeCount(uint tweetId_) public returns (bytes32 requestId) {
        return requestTweetData(tweetId_.toString(), 'public_metrics', 'public_metrics,like_count');
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

    // Internal only
    // **********************************************************************************************
    function _chargeLink() internal {
        if (linkBalance[msg.sender] < fee) {
            revert NotEnoughLink();
        }
        linkBalance[msg.sender] -= fee;
    }

    function toAsciiString(address x) internal pure returns (string memory) {
        // from: https://ethereum.stackexchange.com/a/8447/83136
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        // from: https://ethereum.stackexchange.com/a/8447/83136
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    // Operator only
    // **********************************************************************************************
    /**
    * @notice spends at max 400000 gas when calling the receiver.
    */
    function fulfillInfo(bytes32 requestId_, uint value_) public recordChainlinkFulfillment(requestId_) {
        ITweetRelayerClient requester = ITweetRelayerClient(_requesters[requestId_]);
        requester.onTweetInfoReceived{gas: 400000}(requestId_, value_);
    }

    function fulfillPublication(bytes32 requestId_, uint createdAt_, uint tweetId_) public recordChainlinkFulfillment(requestId_) {
        ITweetRelayerClient requester = ITweetRelayerClient(_requesters[requestId_]);
        requester.onTweetPosted{gas: 400000}(requestId_, createdAt_, tweetId_);
    }
}
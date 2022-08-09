pragma solidity ^0.8.15;

import "../../src/oracle/ITweetRequester.sol";


contract MockTweetRequester is ITweetRequester {
    bytes32 public requestId;
    uint public value;

    function receiveTweetInfo(bytes32 requestId_, uint value_) public {
        requestId = requestId_;
        value = value_;
    }
}
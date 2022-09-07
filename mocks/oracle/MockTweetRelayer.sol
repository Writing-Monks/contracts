// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/oracle/ITweetRelayer.sol";
import "../../src/oracle/ITweetRelayerClient.sol";

error UnableToTransfer();
error NotEnoughLink();


contract MockTweetRelayer is ITweetRelayer {
    IERC20 link;

    mapping(address => uint) public linkBalance;

    constructor(address linkAddress_, address , bytes32 , bytes32 ) {
        link = IERC20(linkAddress_);
    }


    function requestTweetLikeCount(uint tweetId_) public returns (bytes32 requestId) {
        ITweetRelayerClient request = ITweetRelayerClient(msg.sender);
        request.onTweetInfoReceived(requestId_, value_);
        return requestTweetData(tweetId_.toString(), 'public_metrics', 'public_metrics,like_count');
    }


    function depositLink(uint amount_, address to_) public {
        if (!link.transferFrom(msg.sender, address(this), amount_)) {
            revert UnableToTransfer();
        }
        linkBalance[to_] += amount_;
    }

    function withdraw() public {
        uint amount = linkBalance[msg.sender];
        linkBalance[msg.sender] = 0;
        if (!link.transfer(msg.sender, amount)){
            revert UnableToTransfer();
        }
    }

}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "../src/oracle/TweetRelayer.sol";

import "../mocks/oracle/MockLinkToken.sol";
import "../mocks/oracle/MockOperator.sol";
import "../mocks/oracle/MockTweetRelayerClient.sol";


contract TestTweetRelayer is Test {
    uint AMOUNT = 1E18;
    uint tweetId = 1547891527078510592;
    MockTweetRelayerClient requester;

    LinkToken public linkToken;
    MockOperator public mockOperator;
    TweetRelayer public tweetRelayer;
    event Transfer(address indexed from, address indexed to, uint256 amount);


    bytes32 blank_bytes32;

    function setUp() public {
        linkToken = new LinkToken();
        mockOperator = new MockOperator(address(linkToken));
        tweetRelayer = new TweetRelayer(address(linkToken), address(mockOperator));
        requester = new MockTweetRelayerClient();
    }

    function testCanMakeRequestTweetLikeCountNotEnoughLink() public {
        vm.expectRevert(NotEnoughLink.selector);
        tweetRelayer.requestTweetLikeCount(tweetId);
    }

    function testCanMakeRequests() public {
        linkToken.approve(address(tweetRelayer), AMOUNT);
        tweetRelayer.depositLink(AMOUNT, address(requester));

        vm.prank(address(requester));
        bytes32 requestId = tweetRelayer.requestTweetLikeCount(tweetId);
        assertTrue(requestId != blank_bytes32);

        bytes20 postId = bytes20(uint160(0x115));
        vm.prank(address(requester));
        requestId = tweetRelayer.requestTweetPublication(postId);
        assertTrue(requestId != blank_bytes32);

        vm.prank(address(requester));
        requestId = tweetRelayer.requestTweetData(Strings.toString(tweetId), 'yeoeo', '1221,21421');
        assertTrue(requestId != blank_bytes32);
        vm.stopPrank();
    }

    function testCanGetResponse() public {
        linkToken.approve(address(tweetRelayer), AMOUNT);
        tweetRelayer.depositLink(AMOUNT, address(requester));

        vm.prank(address(requester));
        bytes32 requestId = tweetRelayer.requestTweetLikeCount(tweetId);
        mockOperator.fulfillOracleRequest2(requestId, 0.1 ether, address(tweetRelayer), 
            tweetRelayer.fulfillInfo.selector, 5 minutes, abi.encode(requestId, uint(4575))
        );

        assertEq(requester.value(), 4575);
        assertEq(requester.requestId(), requestId);

        vm.prank(address(requester));
        bytes20 postId = bytes20(uint160(0x115));
        bytes32 requestId2 = tweetRelayer.requestTweetPublication(postId);


        mockOperator.fulfillOracleRequest2(requestId2, 0.1 ether, address(tweetRelayer), 
            tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(requestId2,uint(4575), uint(5)));

        assertEq(requester.value(), 4575);
        assertEq(requester.value2(), 5);
    }

    function testWwithdraw() public {
        linkToken.approve(address(tweetRelayer), AMOUNT);
        tweetRelayer.depositLink(AMOUNT, address(0x18));
        vm.prank(address(0x18));

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(tweetRelayer), address(0x18), AMOUNT);
        tweetRelayer.withdraw();

        assertEq(tweetRelayer.linkBalance(address(0x18)), 0);
    }

}

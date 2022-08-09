// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "../src/oracle/TweetInfoRelayer.sol";

import "../mocks/oracle/MockLinkToken.sol";
import "../mocks/oracle/MockOracle.sol";
import "../mocks/oracle/MockTweetRequester.sol";


contract ContractTest is Test {
    uint AMOUNT = 1E18;
    uint tweetId = 1547891527078510592;
    MockTweetRequester requester;

    LinkToken public linkToken;
    MockOracle public mockOracle;
    TweetInfoRelayer public tweetRelayer;
    event Transfer(address indexed from, address indexed to, uint256 amount);


    bytes32 blank_bytes32;

    function setUp() public {
        linkToken = new LinkToken();
        mockOracle = new MockOracle(address(linkToken));
        tweetRelayer = new TweetInfoRelayer(address(linkToken), address(mockOracle));
        requester = new MockTweetRequester();
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

        vm.prank(address(requester));
        requestId = tweetRelayer.requestTweetCreationTimestamp(tweetId);
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
        mockOracle.fulfillOracleRequest(requestId, 4575);

        assertEq(requester.value(), 4575);
        assertEq(requester.requestId(), requestId);
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

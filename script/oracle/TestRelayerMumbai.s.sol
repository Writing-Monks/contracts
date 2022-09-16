// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../src/oracle/TweetRelayer.sol";
import "../../mocks/oracle/MockTweetRelayerClient.sol";


contract RelayerTest is Script, Test {
    address linkAddress = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    address operatorAddress = 0x234C799054D5298777C37F1B8526d895f8D28874;
    bytes32 readTweetJobId = '337cf084c26246539f1b4ea748f35d88';
    bytes32 writeTweetJobId = 'afc6aa0d3a6c48c0bb51aaca5c281f18';
    TweetRelayer tweetRelayer;
    MockTweetRelayerClient client;
    ERC20 linkToken;

    function setUp() public {
        linkToken = ERC20(linkAddress);
        tweetRelayer = TweetRelayer(0x85b568c42FE6360Ee4230Eb220aA79Cfad82ca3d);
        client = MockTweetRelayerClient(0x0865B950a19da6aBFd19521C79846F04aEA20F2d);
    }

    function run() public {
        vm.startBroadcast();
        linkToken.approve(address(tweetRelayer), 0.1 ether);
        tweetRelayer.depositLink(0.1 ether, address(client));
        client.requestTweetPublication(bytes20(uint160(276516459532235791702370163515585966723063106864)), bytes20(0x0));
        //client.requestLikeCount(1570314322307600384);
        //emit log_named_uint('likes:', client.value());
        vm.stopBroadcast();
    }
}

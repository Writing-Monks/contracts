// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "forge-std/Test.sol";


import "../../src/oracle/TweetRelayer.sol";
import "../../mocks/oracle/MockTweetRelayerClient.sol";


contract MumbaiDeployer is Script, Test {
    address linkAddress = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    address operatorAddress = 0x234C799054D5298777C37F1B8526d895f8D28874;
    bytes32 readTweetJobId = '337cf084c26246539f1b4ea748f35d88';
    bytes32 writeTweetJobId = 'afc6aa0d3a6c48c0bb51aaca5c281f18';

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        TweetRelayer tweetRelayer = new TweetRelayer(linkAddress, operatorAddress, readTweetJobId, writeTweetJobId);
        emit log_named_address('TweetRelayer:', address(tweetRelayer));
        MockTweetRelayerClient client = new MockTweetRelayerClient(address(tweetRelayer));
        emit log_named_address('MockClient:', address(client));
        //tweetRelayer.depositLink(0.4 ether, address(client));
        vm.stopBroadcast();        
    }
}

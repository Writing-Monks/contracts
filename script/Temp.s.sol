// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/MonksERC20.sol";
import "../src/core/MonksTypes.sol";
import "../src/MonksMarket.sol";
import "../src/MonksPublication.sol";
import "../src/MonksTestFaucet.sol";

import "../src/oracle/TweetRelayer.sol";
import "../mocks/oracle/MockLinkToken.sol";
import "../mocks/oracle/MockOperator.sol";



contract Temp is Script, Test {
    // Oracle - TO CHANGE
    address public tweetRelayerAddress = 0x85b568c42FE6360Ee4230Eb220aA79Cfad82ca3d;
    TweetRelayer tweetRelayer;
    address linkAddress = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    ERC20 linkToken;
    
    // Publication
    MonksPublication public publication;

    function setUp() public {
        // publication = MonksPublication(0x9c0f31E5052F493E0eE51451d91C7967b08988C2);
        // tweetRelayer = TweetRelayer(tweetRelayerAddress);
        // linkToken = ERC20(linkAddress);
    }

    function run() public {
        // ERC20
        vm.startBroadcast();
        publication;
        vm.stopBroadcast();
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../src/MonksERC20.sol";
import "../src/core/MonksTypes.sol";
import "../src/MonksMarket.sol";
import "../src/MonksPublication.sol";
import "../src/MonksTestFaucet.sol";

import "../src/oracle/TweetRelayer.sol";
import "../mocks/oracle/MockLinkToken.sol";
import "../mocks/oracle/MockOperator.sol";



contract Publish is Script, Test {
    bytes20 postId = bytes20(uint160(310681373696777484921130043273420238295842500920));
    MockOperator mockOperator = MockOperator(0x212cD01Eb23C286587B5CD760843B909a0a6Fd1E);
    MonksPublication pub = MonksPublication(0x2C1803B39e561697D8cfe5b208072D794B2b330E);
    TweetRelayer tweetRelayer = TweetRelayer(0xaaf891C5cfaCE32706595164019450fDEcDAB981);


    // Publication
    address public publicationAdmin = 0xccb4D1786a2d25484957f33F1354cc487bE157CD;
    address coreTeam = address(0x6);
    address postSigner = 0x777C108aCC97d147ba540a99d70704dA36f3D4C2;
    address moderatorsTeam = address(0x6);
    address testUser = 0xccb4D1786a2d25484957f33F1354cc487bE157CD;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // Oracle
        pub.publish(postId);

        uint createdAt = 1656341100;
        uint tweetId = 1570059292560035840;
        emit log_named_bytes32('requestId', mockOperator.lastRequestIdReceived());
        // Note {gas: } is not working yet. use --gas-estimate-multiplier 1000 instead
        // track issue here: https://github.com/foundry-rs/foundry/issues/2627
        mockOperator.fulfillOracleRequest2{gas: 600000}(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), createdAt, tweetId));

        vm.stopBroadcast();
    }
}

contract Resolve is Script, Test {
    bytes20 postId = bytes20(uint160(623560138816845455508020822690762617939091928438));
    MockOperator mockOperator = MockOperator(0x212cD01Eb23C286587B5CD760843B909a0a6Fd1E);
    MonksPublication pub = MonksPublication(0x2C1803B39e561697D8cfe5b208072D794B2b330E);
    TweetRelayer tweetRelayer = TweetRelayer(0xaaf891C5cfaCE32706595164019450fDEcDAB981);


    // Publication
    address public publicationAdmin = 0xccb4D1786a2d25484957f33F1354cc487bE157CD;
    address coreTeam = address(0x6);
    address postSigner = 0x777C108aCC97d147ba540a99d70704dA36f3D4C2;
    address moderatorsTeam = address(0x6);
    address testUser = 0xccb4D1786a2d25484957f33F1354cc487bE157CD;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
    
        uint likes = 202;

        mockOperator.fulfillOracleRequest2{gas: 800000}(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillInfo.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), likes));

        vm.stopBroadcast();
    }
}


// Deploy this locally:
// 1 - Start anvil (type "anvil" on a terminal).
// 2 - forge script script/NFT.s.sol:MyScript --fork-url http://localhost:8545 \
//--private-key $PRIVATE_KEY0 --broadcast
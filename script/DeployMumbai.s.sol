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



contract Deployer is Script, Test {
    // Oracle - TO CHANGE
    address public tweetRelayerAddress = 0x85b568c42FE6360Ee4230Eb220aA79Cfad82ca3d;
    TweetRelayer tweetRelayer;

    // MonksERC20
    uint constant initialSupply = 3000 * 5 * 4 * 3 ether;
    MonksERC20 public token;
    address linkAddress = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    ERC20 linkToken;
    
    // Publication
    MonksPublication public publication;
    MonksTypes.ResultBounds public bounds = MonksTypes.ResultBounds(0, 1000);
    MonksTypes.PayoutSplitBps payoutSplitBps = MonksTypes.PayoutSplitBps(2500, 4000, 2500, 1000);
    uint constant postExpirationPeriod = 3 days;
    uint128[] issuancePerPostType = [3e21];
    int constant alpha = 36067376022224088;
    int[2][] initialQs = [[int(3131115012146561810432), int(3867834985974099607552)]];
    address publicationAdmin = 0x15d2d027c8E2CcD5295E35659B76E61dEF483eE7;
    address coreTeam = 0x15d2d027c8E2CcD5295E35659B76E61dEF483eE7;
    address postSigner = 0x777C108aCC97d147ba540a99d70704dA36f3D4C2;
    address moderatorsTeam = 0x15d2d027c8E2CcD5295E35659B76E61dEF483eE7;
    address testUser = 0x15d2d027c8E2CcD5295E35659B76E61dEF483eE7;

    function setUp() public {
        tweetRelayer = TweetRelayer(tweetRelayerAddress);
        linkToken = ERC20(linkAddress);
    }

    function run() public {
        // ERC20
        vm.startBroadcast();
        publication = new MonksPublication();
        emit log_named_address('Publication address:', address(publication));

        token = new MonksERC20(initialSupply, address(publication), "Monks Test ERC20", "MNK");
        emit log_named_address('Token address:', address(token));

        MonksTestFaucet testFaucet = new MonksTestFaucet(address(token));
        emit log_named_address('Test Token Faucet', address(testFaucet));
        token.transfer(address(testFaucet), 45000 ether);

        linkToken.approve(address(tweetRelayer), 2 ether);
        tweetRelayer.depositLink(2 ether, address(publication));

        // Fund our test user
        token.transfer(testUser, 300 ether);

        // Market Template
        MonksMarket _templateMarket = new MonksMarket();

        // Pub Init
        publication.init(1, postExpirationPeriod, address(_templateMarket), address(token), payoutSplitBps,
                         publicationAdmin, coreTeam, moderatorsTeam, postSigner, 
                         tweetRelayerAddress, bounds);

        publication.setIssuancesForPostType(issuancePerPostType, initialQs, alpha);
        publication.grantRole(MonksTypes.MODERATOR_ROLE, testUser);
        vm.stopBroadcast();
    }
}
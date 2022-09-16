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



contract Deployer is Script, Test {
    // MonksERC20
    uint constant initialSupply = 3000 * 5 * 4 * 3 ether; // three months of posting 
    MonksERC20 public token;
    
    // Oracle
    LinkToken public linkToken;
    MockOperator public mockOperator;
    TweetRelayer public tweetRelayer;
    bytes32 readTweetJobId;
    bytes32 writeTweetJobId;

    // Publication
    MonksPublication public publication;
    MonksTypes.ResultBounds public bounds = MonksTypes.ResultBounds(0, 1000);
    MonksTypes.PayoutSplitBps payoutSplitBps = MonksTypes.PayoutSplitBps(2500, 4000, 2500, 1000);
    uint constant postExpirationPeriod = 3 days;
    uint128[] issuancePerPostType = [3e21];
    int constant alpha = 36067376022224088;
    int[2][] initialQs = [[int(3131115012146561810432), int(3867834985974099607552)]];
    address public publicationAdmin = 0xccb4D1786a2d25484957f33F1354cc487bE157CD;
    address coreTeam = address(0x6);
    address postSigner = 0x777C108aCC97d147ba540a99d70704dA36f3D4C2;
    address moderatorsTeam = address(0x6);
    address testUser = 0xccb4D1786a2d25484957f33F1354cc487bE157CD;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // Oracle
        linkToken = new LinkToken();
        mockOperator = new MockOperator(address(linkToken));
        tweetRelayer = new TweetRelayer(address(linkToken), address(mockOperator), readTweetJobId,
            writeTweetJobId);

        // ERC20
        emit log_named_address('LinkToken:', address(linkToken));
        emit log_named_address('Mock Operator:', address(mockOperator));
        emit log_named_address('TweetRelayer:', address(tweetRelayer));
        publication = new MonksPublication();
        emit log_named_address('Publication address:', address(publication));

        linkToken.approve(address(tweetRelayer), 2 ether);
        tweetRelayer.depositLink(2 ether, address(publication));

        token = new MonksERC20(initialSupply, address(publication), "Monks Test", "TEST");
        emit log_named_address('Token address:', address(token));

        MonksTestFaucet testFaucet = new MonksTestFaucet(address(token));
        token.transfer(address(testFaucet), 45000 ether);
        emit log_named_address('Test Token Faucet', address(testFaucet));
        
        // Fund our user
        token.transfer(testUser, 300 ether);

        // Market Template
        MonksMarket _templateMarket = new MonksMarket();

        // Pub Init
        publication.init(1, postExpirationPeriod, address(_templateMarket), address(token), payoutSplitBps,
                         publicationAdmin, coreTeam, moderatorsTeam, postSigner, 
                         address(tweetRelayer), bounds);

        publication.setIssuancesForPostType(issuancePerPostType, initialQs, alpha);

        publication.grantRole(MonksTypes.MODERATOR_ROLE, testUser);
        vm.stopBroadcast();


        
    }
}


// Deploy this locally:
// 1 - Start anvil (type "anvil" on a terminal).
// 2 - forge script script/NFT.s.sol:MyScript --fork-url http://localhost:8545 \
//--private-key $PRIVATE_KEY0 --broadcast
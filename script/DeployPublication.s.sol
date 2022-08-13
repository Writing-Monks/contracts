// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../src/MonksERC20.sol";
import "../src/core/MonksTypes.sol";
import "../src/MonksMarket.sol";
import "../src/MonksPublication.sol";

import "../src/oracle/TweetRelayer.sol";
import "../mocks/oracle/MockLinkToken.sol";
import "../mocks/oracle/MockOperator.sol";



contract Deployer is Script, Test {
    // MonksERC20
    uint constant initialSupply = 1000E18;
    MonksERC20 public token;
    

    // Oracle
    LinkToken public linkToken;
    MockOperator public mockOperator;
    TweetRelayer public tweetRelayer;

    // Publication
    MonksPublication public publication;
    MonksTypes.ResultBounds public bounds = MonksTypes.ResultBounds(0, 1000);
    MonksTypes.PayoutSplitBps payoutSplitBps = MonksTypes.PayoutSplitBps(1500, 4000, 3000, 1500);
    uint constant postExpirationPeriod = 3 days;
    uint128[] issuancePerPostType = [3e21];
    int constant alpha = 36067376022224088;
    int[2][] initialQs = [[int(3537428612970298998784), int(4424644100154469122048)]];
    address public publicationAdmin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address coreTeam = address(0x6);
    address postSigner = 0x777C108aCC97d147ba540a99d70704dA36f3D4C2;
    address moderatorsTeam = address(0x6);
    address testUser = 0xA12Dd3E2049ebb0B953AD0B01914fF399955924d;

    function setUp() public {}

    function run() public {
        // Oracle
        linkToken = new LinkToken();
        mockOperator = new MockOperator(address(linkToken));
        tweetRelayer = new TweetRelayer(address(linkToken), address(mockOperator));

        // ERC20
        vm.startBroadcast();
        publication = new MonksPublication();
        emit log_named_address('Publication address:', address(publication));

        token = new MonksERC20(initialSupply, address(publication), "Crypto Alpha", "CAL");
        emit log_named_address('Token address:', address(token));
        // Fund our user
        token.transfer(testUser, 300 ether);

        // Market Template
        MonksMarket _templateMarket = new MonksMarket();

        // Pub Init
        publication.init(1, postExpirationPeriod, address(_templateMarket), address(token), payoutSplitBps,
                         publicationAdmin, coreTeam, moderatorsTeam, postSigner, 
                         address(tweetRelayer), bounds);

        publication.setIssuancesForPostType(issuancePerPostType, initialQs, alpha);
        vm.stopBroadcast();


        
    }
}


// Deploy this locally:
// 1 - Start anvil (type "anvil" on a terminal).
// 2 - forge script script/NFT.s.sol:MyScript --fork-url http://localhost:8545 \
//--private-key $PRIVATE_KEY0 --broadcast
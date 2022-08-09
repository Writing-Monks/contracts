// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

// import "../src/MonksERC20.sol";
import "../src/core/MonksTypes.sol";
// import "../src/MonksMarket.sol";
import "../src/MonksPublication.sol";

// import "../src/oracle/TweetInfoRelayer.sol";
// import "../mocks/oracle/MockLinkToken.sol";
// import "../mocks/oracle/MockOracle.sol";



contract Changer is Script, Test {

    MonksPublication public publication;
    address public publicationAdmin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;


    function setUp() public {
        address pubAddress = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
        publication = MonksPublication(pubAddress);
    }

    function run() public {
        // Pub Init
        vm.broadcast(publicationAdmin);
        publication.setResultBounds(MonksTypes.ResultBounds(110, 100000));
    }
}


// Deploy this locally:
// 1 - Start anvil (type "anvil" on a terminal).
// 2 - forge script ChangeParams.s.sol:Changer --fork-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
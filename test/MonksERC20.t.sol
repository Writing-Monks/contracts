// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../src/MonksERC20.sol";
import "forge-std/Test.sol";



contract ContractTest is Test {
    // TODO: Test BaseRelayRecipient
    event Transfer(address indexed from, address indexed to, uint256 amount);
    MonksERC20 public token;
    uint constant initialSupply = 1000E18;
    address constant publicationAddress = address(0x15);


    function setUp() public {
        token = new MonksERC20(initialSupply, publicationAddress, "BLISS", "BLS");
    }

    function testBurnWithoutOwningToken() public {
        vm.prank(publicationAddress);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.burn(1E18);
        vm.stopPrank();
    }

    function testBurn() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), address(0), 1E18);
        token.burn(1E18);
    }

    function testPublishTweetUnauthorized() public {
        vm.expectRevert(TokenUnauthorized.selector);
        token.getPublicationFunding(1e18);
    }

    function testPublishTweetIssuanceTooHigh() public {
        vm.expectRevert(TokenIssuanceTooHigh.selector);
        vm.prank(publicationAddress);
        token.getPublicationFunding(3e21+1);
        vm.stopPrank();
    }

    function testPublishTweet() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), publicationAddress, 1E18);
        vm.prank(publicationAddress);
        token.getPublicationFunding(1e18);
        vm.stopPrank();
    }
}

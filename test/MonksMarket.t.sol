// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "../mocks/MockPublication.sol";
import "../src/interfaces/IMonksPublication.sol";
import "../src/MonksMarket.sol";
import "../src/MonksERC20.sol";
import "../src/core/MonksTypes.sol";
import "../src/MonksMarket.sol";

import "forge-std/Test.sol";

// TODO: test OnTokensRedeemed
contract ContractTest is Test {
    using stdStorage for StdStorage;
    // TODO: more testing regarding resolving and balance > debt
    // setup token
    MonksERC20 public token;
    uint constant initialSupply = 1000E18;

    // setup mock publication
    MockPublication public mockPublication;
    MonksTypes.PayoutSplitBps payoutSplitBps;
    uint constant postExpirationPeriod = 3 days;
    uint128[] issuancePerPostType = [3e21];
    int constant alpha = 36067376022224088;
    uint constant maximumScore = 1;
    int[2][] initialQs = [[int(3537428612970303193088), int(4424644100154474364928)]];
    address public publicationAdmin = address(0x5);
    address coreTeam = address(0x6);
    address postSigner = address(0x7);
    address twitterRelayer = address(0x8);
    MonksTypes.ResultBounds public bounds;

    // setup market
    bytes20 postId = bytes20(uint160(51545));
    uint tweetId = 64415;
    MonksMarket public market;
    MonksTypes.Post public post;
    address author = address(0x1);


    event OnSharesBought(bytes20 indexed postId, address indexed buyer, uint sharesBought, uint cost, bool isYes);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event OnPostFlagged(bytes20 indexed postId, address indexed flaggedBy, bytes32 flagReason);
    event OnPostDeleted(bytes20 indexed postId);

    function setUp() public {
        bounds = MonksTypes.ResultBounds(0, 1000);
        mockPublication = new MockPublication(issuancePerPostType, alpha, initialQs);
        payoutSplitBps = MonksTypes.PayoutSplitBps(1500, 4000, 3000, 1500);

        token = new MonksERC20(initialSupply, address(mockPublication), "BLISS", "BLS");
        post = MonksTypes.Post(0, author, 0);
        market = new MonksMarket();

        mockPublication.init(1, postExpirationPeriod, address(0x2), address(token), payoutSplitBps,
         address(publicationAdmin), coreTeam, address(0x6), postSigner, twitterRelayer, bounds);
        vm.prank(address(mockPublication));                  
        market.init(postId, post);
        vm.stopPrank();
    }

    function testInitMarketAlreadyInitialised() public {
        vm.expectRevert(MarketAlreadyInitialised.selector);
        market.init(postId, post);
    }

    function testBuyShares() public {
        bool isYes = true;
        int sharesToBuy = 1e18;

        // get price to pay
        uint resultInPython = 50089666176972968;
        uint price = market.deltaPrice(sharesToBuy, isYes);
        emit log_named_uint("Price: ", price);
        assertApproxEqAbs(price, resultInPython, 0.00000001E18);

        // approve spender
        token.approve(address(market), price);

        // buy shares
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), address(market), price);

        vm.expectEmit(true, true, true, true);
        emit OnSharesBought(postId, address(this), uint(sharesToBuy), price, isYes);

        market.buy(sharesToBuy, isYes, price);
    }

    function testBuyExceededMaxCost() public {
        bool isYes = true;
        int sharesToBuy = 1e18;

        // get price to pay
        uint resultInPython = 50026880046061704;
        uint price = market.deltaPrice(sharesToBuy, isYes);
        emit log_named_uint("Price: ", price);
        assertApproxEqAbs(price, resultInPython, 0.0001E18);

        // approve spender
        token.approve(address(market), price);

        // buy shares
        vm.expectRevert(MarketExceededMaxCost.selector);
        market.buy(sharesToBuy, isYes, price - 1);
    }

    function testPublishNoAccess() public {
        vm.expectRevert(MarketUnauthorized.selector);
        market.publish();
    }

    function testPublishMarketHasNoBets() public {
        vm.expectRevert(MarketHasNoBets.selector);
        vm.prank(address(mockPublication));
        market.publish();
        vm.stopPrank();
    }

    function testPublish() public {
        testBuyShares();
        vm.prank(address(mockPublication));
        market.publish();
        vm.stopPrank();
    }

    function testResolveNotPublished() public {
        vm.expectRevert(InvalidMarketStatusForAction.selector);
        vm.prank(address(mockPublication));
        market.resolve(0.5e18);
        vm.stopPrank();
    }

    function testResolveMarketIsNotFunded() public {
        testPublish();
        vm.expectRevert(MarketIsNotFunded.selector);
        vm.prank(address(mockPublication));
        market.resolve(0.5e18);
        vm.stopPrank();
    }

    function testResolve() public {
        testPublish();
        uint funding = issuancePerPostType[0] *  payoutSplitBps.editors / 10000;
        token.transfer(address(market), funding);
        vm.prank(address(mockPublication));
        market.resolve(2000);
        assertEq(market.normalisedResult(), 1E18);
        emit log_uint(market.exceeding());
        assertApproxEqAbs(market.exceeding(), 899050089666176876544, 0.0000000001E18);

        vm.prank(address(mockPublication));
        vm.expectRevert(InvalidMarketStatusForAction.selector);
        market.resolve(2000);
        vm.stopPrank();
    }

    // Flagging
    function testFlagUnauthorized() public {
        vm.expectRevert(MarketUnauthorized.selector);
        bytes32 reason = keccak256("Out of topic");
        market.flag(reason);
    }

    function testFlag() public {
        bytes32 reason = keccak256(abi.encodePacked("Out of topic"));
        mockPublication.addRole(MonksTypes.MODERATOR_ROLE, address(this));
        vm.expectEmit(true, true, true, true);
        emit OnPostFlagged(postId, address(this), reason);
        market.flag(reason);
    }

    // Delete
    function testDeleteUnauthorized() public {
        vm.expectRevert(MarketUnauthorized.selector);
        market.deletePost();
    }

    function testDelete() public {
        vm.prank(author);
        vm.expectEmit(true, true, true, true);
        emit OnPostDeleted(postId);
        market.deletePost();
        vm.stopPrank();
    }

}
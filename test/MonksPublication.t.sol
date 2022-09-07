// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "../src/MonksPublication.sol";
import "../src/MonksERC20.sol";
import "../src/core/MonksTypes.sol";
import "../src/MonksMarket.sol";

import "../src/oracle/TweetRelayer.sol";
import "../mocks/oracle/MockLinkToken.sol";
import "../mocks/oracle/MockOperator.sol";

import "forge-std/Test.sol";


contract TestMonksPubContract is Test {
    enum Status {Active, Expired, Flagged, Deleted, Published, Resolved}

    MonksERC20 public token;
    uint constant initialSupply = 1000E18;

    // Oracle
    LinkToken public linkToken;
    MockOperator public mockOperator;
    TweetRelayer public tweetRelayer;
    bytes32 writeTweetJobId;
    bytes32 readTweetJobId;

    // Publication
    bytes20 postId = bytes20(uint160(504715298142089654741934029154195845793245849718));
    MonksTypes.ResultBounds public bounds;
    MonksPublication public publication;
    MonksTypes.PayoutSplitBps payoutSplitBps;
    uint constant postExpirationPeriod = 3 days;
    uint128[] issuancePerPostType = [3e21];
    int constant alpha = 36067376022224088;

    int[2][] initialQs = [[int(3537428612970298998784), int(4424644100154469122048)]];
    address public publicationAdmin = address(0x5);
    address coreTeam = address(0x6);
    //0x777C108aCC97d147ba540a99d70704dA36f3D4C2
    address postSigner = 0x777C108aCC97d147ba540a99d70704dA36f3D4C2;
    uint _pk = 59516206747719513534546244606008062815192359338721313138706269611510327779929;
    // setup template market
    MonksTypes.Post public post;
    address author = address(0x1);


    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    event OnIssuanceParamsUpdated(uint128[] issuancePerPostType_, int[2][] initialQs, int alpha);
    event OnPostMade(address indexed author, bytes20 indexed postId, bytes32 contentHash, int alpha, int[2] initialQ, MonksTypes.ResultBounds bounds);
    event OnPublishedPost(bytes20 indexed postId, address indexed publishedBy, uint coreTeamReward, uint writerReward, uint marketFunding, uint moderationReward);
    event OnTweetPosted(bytes20 indexed postId, uint tweetId, uint deadline);
    event OnMarketResolved(bytes20 indexed postId, uint result);
    event OnTokensRedeemed(bytes20 indexed postId, address indexed redeemer, uint tokensReceived, uint tokensBetted);


    function setUp() public {
        linkToken = new LinkToken();
        mockOperator = new MockOperator(address(linkToken));
        tweetRelayer = new TweetRelayer(address(linkToken), address(mockOperator), readTweetJobId, writeTweetJobId);

        bounds = MonksTypes.ResultBounds(0, 1000);
        publication = new MonksPublication();

        payoutSplitBps = MonksTypes.PayoutSplitBps(1500, 4000, 3000, 1500);
        token = new MonksERC20(initialSupply, address(publication), "BLISS", "BLS");
        post = MonksTypes.Post(0, author, 0);
        MonksMarket _templateMarket = new MonksMarket();

        publication.init(1, postExpirationPeriod, address(_templateMarket), address(token),
                         payoutSplitBps, publicationAdmin, coreTeam, address(0x6), postSigner, 
                             address(tweetRelayer), bounds);

        vm.prank(publicationAdmin);
        vm.expectEmit(true, true, true, true);
        emit Unpaused(publicationAdmin);
        publication.setIssuancesForPostType(issuancePerPostType, initialQs, alpha);
        vm.stopPrank();
    }

    function testSetIssuancesForPostTypeMaximumLossNotCovered() public {
        initialQs = [[initialQs[0][0], initialQs[0][1]+1E18]];
        // uint maximumLoss = publication._getMaxLoss(initialQs[0], alpha, maximumScore);
        // uint marketFunding = issuancePerPostType[0] * payoutSplitBps.moderators / 10000;
        // emit log_named_uint('Loss: ', maximumLoss);
        // emit log_named_uint('Funding: ', marketFunding);
        // emit log_named_uint('Margin: ', marketFunding - maximumLoss);
        vm.prank(publicationAdmin);
        vm.expectRevert(MaximumLossNotCovered.selector);
        publication.setIssuancesForPostType(issuancePerPostType, initialQs, alpha);
        vm.stopPrank();

        initialQs = [[initialQs[0][0]+2E18, initialQs[0][1]]];
        vm.prank(publicationAdmin);
        vm.expectRevert(LooseMargin.selector);
        publication.setIssuancesForPostType(issuancePerPostType, initialQs, alpha);
        vm.stopPrank();
    }

    function testSetIssuancesForPostType() public {
        int[2][] memory _initialQs = initialQs;
        _initialQs[0][0] = 8999999999999982174208;
        _initialQs[0][1] = 8999999999999982174208;
        int _alpha = 72134752044448176;

        vm.prank(publicationAdmin);
        
        vm.expectEmit(true, true, true, true);
        emit OnIssuanceParamsUpdated(issuancePerPostType, _initialQs, _alpha);
        
        publication.setIssuancesForPostType(issuancePerPostType, _initialQs, _alpha); 
    }

    function testAddPostWrongSignature() public {
        bytes32 contentHash = keccak256('This is my post yo.');
        uint8 postType = 0;
        
        // sign message
        bytes32 data = keccak256(abi.encodePacked(address(this), postId, contentHash, postType));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", data));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, message);
        bytes memory signature =  abi.encodePacked(r, s, bytes1(v));

        vm.prank(address(0x8));
        vm.expectRevert(WrongSignature.selector);
        publication.addPost(postId, contentHash, postType, signature);
    }

    function testPostTypeNotSupported() public {    
        bytes32 contentHash = keccak256('This is my post yo.');
        uint8 postType = 1;
        
        // sign message
        bytes32 data = keccak256(abi.encodePacked(address(this), postId, contentHash, postType));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", data));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, message);
        bytes memory signature =  abi.encodePacked(r, s, bytes1(v));

        vm.expectRevert(PostTypeNotSupported.selector);
        publication.addPost(postId, contentHash, postType, signature);
    }

    function testAddPost() public {    
        bytes32 contentHash = keccak256('This is my post yo.');
        
        uint8 postType = 0;
        address tweetAuthor = 0xA12Dd3E2049ebb0B953AD0B01914fF399955924d;

        // sign message
        bytes32 data = keccak256(abi.encodePacked(tweetAuthor, postId, contentHash, postType));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", data));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, message);
        bytes memory signature =  abi.encodePacked(r, s, bytes1(v));

        vm.expectEmit(true, true, true, true);
        emit OnPostMade(tweetAuthor, postId, contentHash, alpha, initialQs[0], bounds);

        vm.prank(tweetAuthor);
        publication.addPost(postId, contentHash, postType, signature);
    }

    function testAddPostTwice() public {    
        bytes32 contentHash = keccak256('This is my post yo.');
        
        uint8 postType = 0;
        
        // sign message
        bytes32 data = keccak256(abi.encodePacked(address(this), postId, contentHash, postType));
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", data));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, message);
        bytes memory signature =  abi.encodePacked(r, s, bytes1(v));

        vm.expectEmit(true, true, true, true);
        emit OnPostMade(address(this), postId, contentHash, alpha, initialQs[0], bounds);
        publication.addPost(postId, contentHash, postType, signature);
        
        // Shouldn't be able to post the same thing twice
        vm.expectRevert("ERC1167: create2 failed");
        publication.addPost(postId, contentHash, postType, signature);
    }

    function testSetPayoutSplitBpsDoesntSumToOne() public {
        vm.prank(publicationAdmin);
        MonksTypes.PayoutSplitBps memory split = MonksTypes.PayoutSplitBps(1500, 4000, 1000, 1500);
        vm.expectRevert(DoesntSumToOne.selector);
        publication.setPayoutSplitBps(split);
        vm.stopPrank();
    }

    function testSetPayoutSplitBps() public {
        vm.prank(publicationAdmin);
        MonksTypes.PayoutSplitBps memory split = MonksTypes.PayoutSplitBps(1500, 5000, 2000, 1500);
        vm.expectEmit(true, true, true, true);
        emit Paused(publicationAdmin);
        publication.setPayoutSplitBps(split);
        vm.stopPrank();
    }

    function testPublishNoAccess() public {
        testAddPost();
        MonksMarket market = MonksMarket(publication.getMarketAddressOf(postId));
        buyShares(market, 1E18);

        //depositLinkTo(address(publication), 1E18 / 10);
        vm.expectRevert(bytes(abi.encodePacked("AccessControl: account ",
         Strings.toHexString(address(this))," is missing role ", Strings.toHexString(uint256(keccak256('MODERATOR')), 32)
         )));
        publication.publish(postId);


        address moderator = address(0x85);
        giveModeratorRightTo(moderator);
        
        vm.prank(moderator);
        vm.expectRevert(NotEnoughLink.selector);
        vm.warp(block.timestamp + 13 hours);
        publication.publish(postId);
    }

    function testPublish() public returns (uint) {
        address moderator = address(0x85);
        giveModeratorRightTo(moderator);

        testAddPost();
        IMonksMarket market = IMonksMarket(publication.getMarketAddressOf(postId));
        uint cost = buyShares(market, 1E18);

        depositLinkTo(address(publication), 1E18 / 10);

        // link from relayer [from the balance of the pub] to oracle 
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(tweetRelayer), address(mockOperator), 1E18 / 10);

        // minted new mockERC20
        uint funding = issuancePerPostType[0];
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0x0), address(publication), funding);

        uint marketFunding = funding * payoutSplitBps.editors / 10000;
        uint writersReward = funding * payoutSplitBps.writer / 10000;
        uint moderatorsReward = funding * payoutSplitBps.moderators / 10000;
        uint coreTeamReward = funding * payoutSplitBps.coreTeam / 10000;
        uint[4] memory rewards = [writersReward, marketFunding, moderatorsReward, coreTeamReward];
        address[4] memory addresses = [market.author(), address(market), address(0x6), coreTeam];

        for (uint i = 0; i < 4; i++) {
            vm.expectEmit(true, true, true, true);
            emit Transfer(address(publication), addresses[i], rewards[i]);
        }

        vm.expectEmit(true, true, true, true);
        emit OnPublishedPost(postId, moderator, coreTeamReward, writersReward, marketFunding, moderatorsReward);

        vm.prank(moderator);
        vm.warp(block.timestamp + 13 hours);
        publication.publish(postId);
        vm.stopPrank();
        return cost;
    }

    function testPublishTwice () public {
        address moderator = address(0x85);
        depositLinkTo(address(publication), 1E18 / 10);
        testPublish();

        vm.prank(moderator);
        vm.expectRevert(InvalidMarketStatusForAction.selector);
        vm.warp(block.timestamp + 13 hours);
        publication.publish(postId);
        vm.stopPrank();
    }

    function testOnTweetPosted() public {
        testPublish();

        vm.expectEmit(true, true, true, true);
        uint tweetId = 1545;
        emit OnTweetPosted(postId, tweetId, 1656341100 + 1 days);

        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 1656341100, tweetId));
    }

    function testReceivingOnTweetPostTwice() public {
        uint tweetId = 1545;
        depositLinkTo(address(publication), 1E18 / 10);
        testPublish();

        vm.expectEmit(true, true, true, true);
        emit OnTweetPosted(postId, tweetId, 1656341100 + 1 days);
        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 1656341100, tweetId));

        IMonksMarket market = IMonksMarket(publication.getMarketAddressOf(postId));
        assertEq(market.publishTime(), 1656341100);
        assertEq(market.tweetId(), tweetId);

        vm.prank(publicationAdmin);
        publication.requestTweetPublication(postId);

        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 2, 5));
        
        // Did not change   
        assertEq(market.publishTime(), 1656341100);
        assertEq(market.tweetId(), tweetId);
    }

    function testResolveBeforeDeadline() public {
        testPublish();

        vm.expectRevert(MarketDeadlineNotYetReached.selector);
        publication.resolve(postId);
        
        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 1656341100, 5));

        vm.warp(1656341100 + 12 hours);
        vm.expectRevert(MarketDeadlineNotYetReached.selector);
        publication.resolve(postId);
    }

    function testResolve() public {
        testPublish();
        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 1656341100, 5));
        
        depositLinkTo(address(publication), 1E17);

        vm.warp(1656341100 + 1 days + 1);
        publication.resolve(postId);

        vm.expectRevert(ResolveRequestAlreadyMade.selector);
        publication.resolve(postId);
    }

    function testRedeem() public {
        uint cost = testPublish();
        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 1656341100, 5));
        
        depositLinkTo(address(publication), 2E17);

        vm.warp(1656341100 + 1 days + 1);
        publication.resolve(postId);

        vm.expectRevert(ResolveRequestAlreadyMade.selector);
        publication.resolve(postId);

        // 50 likes
        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillInfo.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 1000));

        address _marketAddress = publication.getMarketAddressOf(postId);
        MonksMarket market = MonksMarket(_marketAddress);
        //emit log_uint(market.exceeding());
        //emit log_uint(market.funding() * payoutSplitBps.editors/10000);
        //emit log_uint(uint(market.normalisedResult()) * 1 + market.funding() * payoutSplitBps.editors/10000);
        
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(market), address(this), 900050089666177505526);
        vm.expectEmit(true, true, true, true);
        emit OnTokensRedeemed(postId, address(this), 900050089666177505526, cost);
        market.redeemAll();
    }

    function testReceiveLikeCount() public {
        testPublish();
        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillPublication.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 1656341100, 5));
        depositLinkTo(address(publication), 2E17);

        vm.warp(1656341100 + 1 days + 1);
        publication.resolve(postId);

        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillInfo.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 50));
        
        MonksMarket market = MonksMarket(publication.getMarketAddressOf(postId));

        assertEq(market.normalisedResult(), 50*1E18 / 1000);
        assertTrue(market.status() == MonksMarket.Status.Resolved);

        vm.prank(publicationAdmin);
        publication.requestLikeCount(postId);
        mockOperator.fulfillOracleRequest2(mockOperator.lastRequestIdReceived(), 0.1 ether, address(tweetRelayer),
        tweetRelayer.fulfillInfo.selector, 5 minutes, abi.encode(mockOperator.lastRequestIdReceived(), 43));
        assertEq(market.normalisedResult(), 50*1E18 / 1000); //did not change
    }

    function depositLinkTo(address to, uint amount) public {
        linkToken.approve(address(tweetRelayer), amount);
        tweetRelayer.depositLink(amount, to);
    }

    function giveModeratorRightTo(address newModerator) public {
        vm.prank(publicationAdmin);
        publication.grantRole(MonksTypes.MODERATOR_ROLE, newModerator);
        vm.stopPrank();
    }

    function buyShares(IMonksMarket market, int sharesToBuy) public returns (uint) {
        uint cost = market.deltaPrice(sharesToBuy, true);
        token.approve(address(market), cost);
        market.buy(sharesToBuy, true, cost);
        return cost;
    }

}
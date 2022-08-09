// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "../src/MonksPublication.sol";
import "../src/MonksERC20.sol";
import "../src/core/MonksTypes.sol";
import "../src/MonksMarket.sol";

import "../src/oracle/TweetInfoRelayer.sol";
import "../mocks/oracle/MockLinkToken.sol";
import "../mocks/oracle/MockOracle.sol";

import "forge-std/Test.sol";

// TODO: resolve, 
contract ContractTest is Test {
    MonksERC20 public token;
    uint constant initialSupply = 1000E18;

    // Oracle
    LinkToken public linkToken;
    MockOracle public mockOracle;
    TweetInfoRelayer public tweetRelayer;

    // publication
    
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
    event OnPostMade(address indexed author, bytes20 postId, bytes32 contentHash, int alpha, int[2] initialQ, MonksTypes.ResultBounds bounds);
    event OnPublishedPost(bytes20 postId, uint coreTeamReward, uint journalistReward, uint marketFunding);
    event OnMarketDeadlineSet(bytes20 indexed postId, uint deadline);
    event OnMarketResolved(bytes20 indexed postId, uint result);

    
    function setUp() public {
        linkToken = new LinkToken();
        mockOracle = new MockOracle(address(linkToken));
        tweetRelayer = new TweetInfoRelayer(address(linkToken), address(mockOracle));

        bounds = MonksTypes.ResultBounds(0, 1000);
        publication = new MonksPublication();

        payoutSplitBps = MonksTypes.PayoutSplitBps(3000, 4000, 3000);
        token = new MonksERC20(initialSupply, address(publication), "BLISS", "BLS");
        post = MonksTypes.Post(0, author, 0);
        MonksMarket _templateMarket = new MonksMarket();

        publication.init(1, postExpirationPeriod, address(_templateMarket), address(0x6),
                             address(token), payoutSplitBps, publicationAdmin, coreTeam, postSigner, 
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
        // uint marketFunding = issuancePerPostType[0] * payoutSplitBps.editors / 10000;
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
        emit log_named_bytes('PostId: ', abi.encodePacked(postId));
        emit log_named_bytes32('ContentHash: ', contentHash);
        emit log_named_uint('Post type: ', postType);
        emit log_named_bytes('Signature:', signature);
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
        MonksTypes.PayoutSplitBps memory split = MonksTypes.PayoutSplitBps(3000, 4000, 1500);
        vm.expectRevert(DoesntSumToOne.selector);
        publication.setPayoutSplitBps(split);
        vm.stopPrank();
    }

    function testSetPayoutSplitBps() public {
        vm.prank(publicationAdmin);
        MonksTypes.PayoutSplitBps memory split = MonksTypes.PayoutSplitBps(3000, 5000, 2000);
        vm.expectEmit(true, true, true, true);
        emit Paused(publicationAdmin);
        publication.setPayoutSplitBps(split);
        vm.stopPrank();
    }

    function testPublishNoAccess() public {
        testAddPost();
        IMonksMarket market = IMonksMarket(publication.getMarketAddressOf(postId));
        buyShares(market, 1E18);

        vm.expectRevert(bytes(abi.encodePacked("AccessControl: account ",
         Strings.toHexString(address(this))," is missing role ", Strings.toHexString(uint256(keccak256('EDITOR')), 32)
         )));
        publication.publish(postId, 123141);


        address editor = address(0x85);
        giveEditorRightTo(editor);
        vm.prank(editor);

        vm.expectRevert(NotEnoughLink.selector);
        publication.publish(postId, 123141);
    }

    function testPublish() public {
        address editor = address(0x85);
        giveEditorRightTo(editor);

        testAddPost();
        IMonksMarket market = IMonksMarket(publication.getMarketAddressOf(postId));
        buyShares(market, 1E18);

        depositLinkTo(address(publication), 1E18 / 10);

        // link from relayer [from the balance of the pub] to oracle 
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(tweetRelayer), address(mockOracle), 1E18 / 10);

        // minted new mockERC20
        uint funding = issuancePerPostType[0];
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0x0), address(publication), funding);

        uint marketFunding = funding * payoutSplitBps.editors / 10000;
        uint writersReward = funding * payoutSplitBps.writer / 10000;
        uint coreTeamReward = funding - marketFunding - writersReward;
        uint[3] memory rewards = [writersReward, marketFunding, coreTeamReward];
        address[3] memory addresses = [market.author(), address(market), coreTeam];

        for (uint i = 0; i < 3; i++) {
            vm.expectEmit(true, true, true, true);
            emit Transfer(address(publication), addresses[i], rewards[i]);
        }

        vm.expectEmit(true, true, true, true);
        emit OnPublishedPost(postId, coreTeamReward, writersReward, marketFunding);
        vm.prank(editor);
        publication.publish(postId, 123141);
        vm.stopPrank();
    }

    function testPublishTwice () public {
        address editor = address(0x85);
        depositLinkTo(address(publication), 1E18 / 10);
        testPublish();

        vm.prank(editor);
        vm.expectRevert(InvalidMarketStatusForAction.selector);
        publication.publish(postId, 123141);
        vm.stopPrank();
    }

    function testReceivingCreationTime() public {
        testPublish();

        vm.expectEmit(true, true, true, true);
        emit OnMarketDeadlineSet(postId, 1656341100 + 1 days);
        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 1656341100);
    }

    function testReceivingCreationTimeTwice() public {
        depositLinkTo(address(publication), 1E18 / 10);
        testPublish();

        vm.expectEmit(true, true, true, true);
        emit OnMarketDeadlineSet(postId, 1656341100 + 1 days);
        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 1656341100);

        IMonksMarket market = IMonksMarket(publication.getMarketAddressOf(postId));
        assertEq(market.publishTime(), 1656341100);

        vm.prank(publicationAdmin);
        publication.requestTwitterInfo(postId, 123141, false);

        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 2);
        assertEq(market.publishTime(), 1656341100); // Did not change        
    }

    function testResolveBeforeDeadline() public {
        testPublish();

        vm.expectRevert(MarketDeadlineNotYetReached.selector);
        publication.resolve(postId);

        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 1656341100);

        vm.warp(1656341100 + 12 hours);
        vm.expectRevert(MarketDeadlineNotYetReached.selector);
        publication.resolve(postId);
    }

    function testResolve() public {
        testPublish();
        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 1656341100);
        depositLinkTo(address(publication), 1E17);

        vm.warp(1656341100 + 1 days + 1);
        publication.resolve(postId);

        vm.expectRevert(ResolveRequestAlreadyMade.selector);
        publication.resolve(postId);
    }

    function testReceiveLikeCount() public {
        testPublish();
        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 1656341100);
        depositLinkTo(address(publication), 2E17);

        vm.warp(1656341100 + 1 days + 1);
        publication.resolve(postId);

        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 50);
        MonksMarket market = MonksMarket(publication.getMarketAddressOf(postId));

        assertEq(market.normalisedResult(), 50*1E18 / 1000);
        assertTrue(market.status() == MonksMarket.Status.Resolved);

        vm.prank(publicationAdmin);
        publication.requestTwitterInfo(postId, 1, true);
        mockOracle.fulfillOracleRequest(mockOracle.lastRequestIdReceived(), 43);
        assertEq(market.normalisedResult(), 50*1E18 / 1000); //did not change
    }

    function depositLinkTo(address to, uint amount) public {
        linkToken.approve(address(tweetRelayer), amount);
        tweetRelayer.depositLink(amount, to);
    }

    function giveEditorRightTo(address newEditor) public {
        bytes32 role = keccak256('EDITOR');
        vm.prank(publicationAdmin);
        publication.grantRole(role, newEditor);
        vm.stopPrank();
    }

    function buyShares(IMonksMarket market, int sharesToBuy) public {
        uint cost = market.deltaPrice(sharesToBuy, true);
        token.approve(address(market), cost);
        market.buy(sharesToBuy, true, cost);
    }

}
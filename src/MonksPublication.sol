// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@opengsn/contracts/src/ERC2771Recipient.sol";

import './oracle/ITweetRelayerClient.sol';
import './oracle/ITweetRelayer.sol';
import './interfaces/IMonksPublication.sol';
import './interfaces/IMonksMarket.sol';
import './interfaces/IMonksAuction.sol';
import './PRBMathSD59x18.sol';

error Unauthorized();
error CantPublishThisFast();
error PostTypeNotSupported();
error WrongSignature();
error DoesntSumToOne();
error MaximumLossNotCovered();
error LooseMargin();
error MarketDeadlineNotYetReached();
error ResolveRequestAlreadyMade();
error UnknownRequestId();


contract MonksPublication is ERC2771Recipient, IMonksPublication, ITweetRelayerClient, Pausable, AccessControl {
    using PRBMathSD59x18 for int;
    using ECDSA for bytes32;

    // After publication each tweet will accumulate likes for `ACCUMULATION_PERIOD` and then chainlink can read how many likes it got and settle the prediction market.
    uint constant private ACCUMULATION_PERIOD = 10 minutes;//1 days; 

    // Public variables
    // ***************************************************************************************
    // Each address has a writing and a predicting score. Which correspond to how much profit the address had doing those two activities.
    // This could be used for a reputation score, soulbound NFTs, curriculum vitae, access, voting power, etc..
    mapping(address => uint[2]) public scores; 
    uint public postExpirationPeriod = 3 days;  // After `postExpirationPeriod` of being submitted, if the post is not published it expires and betters can get a full refund of their bets.
    mapping(address => uint) public modLastPublication;
    uint public publicationRate = 12 hours; // each mod can publish once every publicationRate

    // How much to pay for each type of post
    // Example of different types of posts may be: memes, news stories, opinion articles, etc..
    uint128[] public issuancePerPostType;  
    MonksTypes.PayoutSplitBps public payoutSplitBps;  // How is that issuance split amongst: protocol fees, writer, market and moderators.
    IMonksERC20 public monksERC20;  // The token being issued.
    
    // Variables that define the initial conditions and properties of the predictive market:
    int public alpha;
    MonksTypes.ResultBounds public bounds;
    int[2][] public initialQs; // for each postType we have a 2D array with the initial Yes and No shares.

    // Private variables
    // ***************************************************************************************
    address private _coreTeam;  // address where the protocol fees will be sent
    address private _moderationTeam;  // address where the moderators pay will be sent
    address private _marketTemplate;  // address of the predictive market contract template
    address private _postSigner;  // address that signs the posts being submitted
    address private _monksAuction;  // Where sponsores make bids for sponsored tweets
    
    // Oracle variables:
    ITweetRelayer private _twitterRelayer;  // contract that relays the information from the oracle
    mapping(bytes20 => bool) private _resolveRequestMade; // {postId: bool} - whether the contract already asked chainlink to get the like count on the post
    mapping(bytes32 => bytes20) private _likeCountRequests; // mapping from requestId to postId for requests on like counts
    mapping(bytes32 => bytes20) private _publicationRequests; // mapping from requestId to postId for requests on creation date

    bool private _isInitialised;
    event OnPublicationInitialised(uint64 id, MonksTypes.PayoutSplitBps payoutSplitBps, MonksTypes.ResultBounds bounds, address tokenAddress);
    event OnIssuanceParamsUpdated(uint128[] issuancePerPostType, int[2][] initialQs, int alpha);
    event OnResultBoundsUpdated(MonksTypes.ResultBounds bounds);
    event OnPostMade(address indexed author, bytes20 indexed postId, bytes32 contentHash, int alpha, int[2] initialQ, MonksTypes.ResultBounds bounds);
    event OnPublishedPost(bytes20 indexed postId, bytes20 indexed adId, address indexed publishedBy, uint coreTeamReward, uint writerReward, uint marketFunding, uint moderationReward);
    event OnTweetPosted(bytes20 indexed postId, uint tweetId, uint deadline);
    event OnMarketResolved(bytes20 indexed postId, uint result);
    event OnPostExpirationPeriodUpdated(uint newPostExpirationPeriod);

    // Events triggered by the Market contract
    event OnPostFlagged(bytes20 indexed postId, address indexed flaggedBy, bytes32 flagReason);
    event OnPostDeleted(bytes20 indexed postId);
    event OnSharesBought(bytes20 indexed postId, address indexed buyer, uint sharesBought, uint cost, bool isYes);
    event OnTokensRedeemed(bytes20 indexed postId, address indexed redeemer, uint tokensReceived, uint tokensBetted);
    event OnRefundTaken(bytes20 indexed postId, address indexed to, uint value);


    function init (uint64 publicationId_, uint postExpirationPeriod_, address marketTemplate_, address token_, MonksTypes.PayoutSplitBps memory payoutSplitBps_,
                   address publicationAdmin_, address coreTeam_, address moderationTeam_,
                   address postSigner_, address twitterRelayer_, MonksTypes.ResultBounds memory bounds_)
                   public validPayoutSplitBps(payoutSplitBps_){
        require(!_isInitialised);

        _twitterRelayer = ITweetRelayer(twitterRelayer_);
        postExpirationPeriod = postExpirationPeriod_;
        _marketTemplate = marketTemplate_;
        monksERC20 = IMonksERC20(token_);
        _moderationTeam = moderationTeam_;
        _coreTeam = coreTeam_;
        _postSigner = postSigner_;
        payoutSplitBps = payoutSplitBps_;
        bounds = bounds_;

        _isInitialised = true;
        emit OnPublicationInitialised(publicationId_, payoutSplitBps_, bounds_, token_);

        _setupRole(DEFAULT_ADMIN_ROLE, publicationAdmin_);
        // The publication starts paused
        _pause();
    }

    /**
     * @notice anyone can resolve a market once its deadline.
     * This function asks our chainlink oracle to tell us how many likes the post has.
     * So this function costs LINK to the publication. 
     */
    function resolve(bytes20 postId_) public {
        if (_resolveRequestMade[postId_]) {
            // To save LINK, this function can only be called once.
            revert ResolveRequestAlreadyMade();
        }
        address marketAddress = getMarketAddressOf(postId_);

        // Check if accumulation period was respected
        IMonksMarket market = IMonksMarket(marketAddress);        
        uint publishTime = market.publishTime();
        if (publishTime == 0 || publishTime + ACCUMULATION_PERIOD > block.timestamp) {
            revert MarketDeadlineNotYetReached();
        }

        _resolveRequestMade[postId_] = true;

        // Request info to the chainlink oracle
        _requestLikeCount(postId_, marketAddress);
    }

    function buyFromMarket(bytes20 postId_, int sharesToBuy_, bool isYes_, uint maximumCost_) public {
        require(sharesToBuy_ > 0);
        IMonksMarket market = IMonksMarket(getMarketAddressOf(postId_));
        if (market.status() != IMonksMarket.Status.Active) {
            revert InvalidMarketStatusForAction();
        }
        uint amountToPay = market.deltaPrice(sharesToBuy_, isYes_);
        if (amountToPay > maximumCost_) {
            revert MarketExceededMaxCost();
        }
        monksERC20.transferFrom(_msgSender(), address(market), amountToPay);
        market.buy(sharesToBuy_, isYes_, amountToPay, _msgSender());
        emit OnSharesBought(postId_, _msgSender(), uint(sharesToBuy_), amountToPay, isYes_);
    }

    /**
     * @param postId_ unique identifier of the post
     * @param contentHash_ keccack256(text content of tweets) - could be useful to prove ownership and plagiarism.
     * @param postType_ different postTypes need to respect different guidelines and have different rewards
     * @param signature_ our server signature ensures that we have stored the unhashed content on our end
     */
    function addPost(bytes20 postId_, bytes32 contentHash_, uint8 postType_, bytes calldata signature_) public whenNotPaused {
        if (postType_ >= initialQs.length) {
            revert PostTypeNotSupported();
        }
        if (!_verify(abi.encodePacked(_msgSender(), postId_, contentHash_, postType_), signature_)) {
            // We co-sign this transaction for two reasons:
            // 1 - Ensure that the author of this post is not front-runned by a bot and therefore it can prove that she/he was the first to post
            // 2 - It guarantees that we have the unhashed content stored on our end
            revert WrongSignature();
        }
         
        MonksTypes.Post memory post = MonksTypes.Post(postType_, _msgSender(), block.timestamp);

        _createMarket(postId_, post);

        emit OnPostMade(_msgSender(), postId_, contentHash_, alpha, initialQs[postType_], bounds);
    }

    // Getters
    // ***************************************************************************************
    
    function getMarketAddressOf(bytes20 postId_) public view returns (address) {
        return Clones.predictDeterministicAddress(_marketTemplate, keccak256(abi.encodePacked(postId_)), address(this));
    }

    function totalScore(address monk) public view returns (uint) {
        return scores[monk][0] + scores[monk][1];
    }

    // Only Internal Functions
    // ***************************************************************************************
    function _getMaxLoss(int[2] calldata q_, int alpha_) public pure returns (uint) {
        int r = q_[0].div(q_[1]);
        int qSum = q_[0]+ q_[1];
        int denominator = alpha_.mul(r+1E18);
        int e_ra = r.div(denominator).exp();
        int e_a = denominator.inv().exp();
        if (r < 1E18) {
            return uint(qSum.mul(alpha_.mul((e_ra+e_a).ln())-r.div(r+1E18)));
        } else {
            return uint(qSum.mul(alpha_.mul((e_ra+e_a).ln())-(r+1E18).inv()));
        }
    }

    function _createMarket(bytes20 postId_, MonksTypes.Post memory post_) internal {
        IMonksMarket clone = IMonksMarket(Clones.cloneDeterministic(_marketTemplate, keccak256(abi.encodePacked(postId_))));
        clone.init(postId_, post_);
    }

    function _verify(bytes memory message, bytes calldata signature_) internal view returns (bool){
        return keccak256(message).toEthSignedMessageHash().recover(signature_) == _postSigner;
    }

    function _requestTweetPublication(bytes20 postId_, bytes20 adId_) internal {
        bytes32 requestId = _twitterRelayer.requestTweetPublication(postId_, adId_);
        _publicationRequests[requestId] = postId_;
    }

    function _requestLikeCount(bytes20 postId_, address marketAddress) internal {
        IMonksMarket market = IMonksMarket(marketAddress);
        bytes32 requestId = _twitterRelayer.requestTweetLikeCount(market.tweetId());
        _likeCountRequests[requestId] = postId_;
    }

    // Setters
    // ***************************************************************************************
    function setIssuancesForPostType(uint128[] calldata issuancePerPostType_, int[2][] calldata initialQs_,
        int alpha_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(issuancePerPostType_.length == initialQs_.length);
        uint _maxIssuancePerPost = monksERC20.maxIssuancePerPost() + 1;
        for (uint8 i = 0; i < issuancePerPostType_.length; i++) {
            require(issuancePerPostType_[i] < _maxIssuancePerPost);
            uint maximumLoss = _getMaxLoss(initialQs_[i], alpha_);
            uint marketFunding = issuancePerPostType_[i] * payoutSplitBps.editors / 10000;
            if (marketFunding < maximumLoss) {
                revert MaximumLossNotCovered();
            }
            if (marketFunding - maximumLoss > 1e10) {
                // Market funding is bigger than the theoretical maximum loss by a big margin.
                // It's hard to compute marketFunding==maximumLoss but this would give us the best initial liquidity.
                revert LooseMargin();
            }
        }

        initialQs = initialQs_;
        issuancePerPostType = issuancePerPostType_;
        alpha = alpha_;

        emit OnIssuanceParamsUpdated(issuancePerPostType_, initialQs_, alpha_);

        if (paused()) {
            _unpause();
        }
    }

    function setResultBounds(MonksTypes.ResultBounds calldata value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        bounds = value_;
        emit OnResultBoundsUpdated(value_);
    }

    function setCoreTeamAddress(address value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _coreTeam = value_;
    }

    function setMarketTemplate(address value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _marketTemplate = value_;
    }

    function setPostSigner(address value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _postSigner = value_;
    }

    function setPayoutSplitBps(MonksTypes.PayoutSplitBps calldata payoutSplitBps_) public validPayoutSplitBps(payoutSplitBps_) onlyRole(DEFAULT_ADMIN_ROLE) {
        if (payoutSplitBps.editors != payoutSplitBps_.editors) {
            // Our issuance for the market is now invalid, we need to re-call setIssuancesForPostType with valid params.
            _pause();
            payoutSplitBps = payoutSplitBps_;
        }
    }

    function setPostExpirationPeriod(uint value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        postExpirationPeriod = value_;
        emit OnPostExpirationPeriodUpdated(value_);
    }

    function setModerationTeam(address value) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _moderationTeam = value;
    }

    function setPublicationRate(uint value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        publicationRate = value_;
    }

    function setTrustedForwarder(address value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTrustedForwarder(value_);
    }

    function setMonksAuction(address value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _monksAuction = value_;
    }

    function setTwitterRelayer(address value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _twitterRelayer = ITweetRelayer(value_);
    }

    // Editor and Admin Functions
    // ***************************************************************************************

    /**
    *  Asks the twitter oracle to get the timestamp for when the tweet was published, this will be used
    *  to set the deadline on the predictive market.
    *  Pays the writer and the core team and funds the predictive market.
    */

    function publish(bytes20 postId_) public onlyRole(MonksTypes.MODERATOR_ROLE) {
        if (modLastPublication[_msgSender()] + publicationRate > block.timestamp) {
            revert CantPublishThisFast();
        }
        modLastPublication[_msgSender()] = block.timestamp;

        IMonksMarket market = IMonksMarket(getMarketAddressOf(postId_));
        (uint8 postType, address author) = market.postTypeAndAuthor();

        // If this publication is accepting sponsored tweets, request a sponsored tweet to be posted
        bytes20 adId;
        if (_monksAuction != address(0x0)) {
            adId = IMonksAuction(_monksAuction).getSponsorForPostType(postType);
        }

        _requestTweetPublication(postId_, adId);

        uint funding = market.funding();

        // Get funding to publish tweet
        monksERC20.getPublicationFunding(funding);

        // Publish
        market.publish();

        // Compute the payout to coreTeam, writer and editors
        MonksTypes.PayoutSplitBps memory _marketPayoutSplit = market.payoutSplitBps();
        uint _marketFunding = funding * _marketPayoutSplit.editors / 10000;
        uint _writersReward = funding * _marketPayoutSplit.writer / 10000;
        uint _moderatorsReward = funding * _marketPayoutSplit.moderators / 10000;
        uint _coreTeamReward = funding * _marketPayoutSplit.coreTeam / 10000;
        
        // Pay out
        monksERC20.transfer(author, _writersReward);
        monksERC20.transfer(address(market), _marketFunding);
        monksERC20.transfer(_moderationTeam, _moderatorsReward);
        monksERC20.transfer(_coreTeam, _coreTeamReward);

        scores[author][0] += _writersReward;
        emit OnPublishedPost(postId_, adId, _msgSender(), _coreTeamReward, _writersReward, _marketFunding, _moderatorsReward);
    }

    /**
    * @notice `_requestTweetPublication` is called by the publish function. However, it can also be called manually by an admin, which is useful, 
    * if an error occurs with the chainlink oracle and we need to repeat a request.
    * The market will not override the tweet id && creation date if it was already successfully set.
    */
    function requestTweetPublication(bytes20 postId_, bytes20 adId_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _requestTweetPublication(postId_, adId_);
    }

    /**
    * @notice `_requestLikeCount` is called by the resolve function. However, it can also be called manually by an admin, which is useful, 
    * if an error occurs with the chainlink oracle and we need to repeat a request.
    * The market will not override the like count if it was already successfully set.
    */
    function requestLikeCount(bytes20 postId_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _requestLikeCount(postId_, getMarketAddressOf(postId_));
    }

    // TwitterRelayerClient Functions
    // ***************************************************************************************
    function onTweetInfoReceived(bytes32 requestId_, uint value_) public onlyTweetRelayer {
        if (_likeCountRequests[requestId_] == 0) {
            revert UnknownRequestId();
        }
        bytes20 postId = _likeCountRequests[requestId_];
        IMonksMarket market = IMonksMarket(getMarketAddressOf(postId));
        market.resolve(value_);
        emit OnMarketResolved(postId, value_);
    }

    function onTweetPosted(bytes32 requestId_, uint createdAt_, uint tweetId_) public onlyTweetRelayer {
        if (_publicationRequests[requestId_] == 0) {
            revert UnknownRequestId();
        }
        bytes20 postId = _publicationRequests[requestId_];
        IMonksMarket market = IMonksMarket(getMarketAddressOf(postId));
        market.setPublishTimeAndTweetId(createdAt_, tweetId_);
        emit OnTweetPosted(postId, tweetId_, createdAt_ + ACCUMULATION_PERIOD);
    }


    // Modifiers
    // ***************************************************************************************
    modifier onlyTweetRelayer(){
        if (msg.sender != address(_twitterRelayer)) {
            revert Unauthorized();
        }
        _;
    }

    modifier validPayoutSplitBps(MonksTypes.PayoutSplitBps memory payoutSplitBps_) {
        if (payoutSplitBps_.coreTeam + payoutSplitBps_.writer + payoutSplitBps_.editors + payoutSplitBps_.moderators != 10000){
            revert DoesntSumToOne();
        }
        _;
    }

    modifier onlyMarket(bytes20 postId_) {
        if (msg.sender != getMarketAddressOf(postId_)) {
            revert Unauthorized();
        }
        _;
    }


    // Market Functions That Trigger Events
    // ***************************************************************************************
    function emitOnPostFlagged(bytes20 postId_, address flaggedBy_, bytes32 flagReason_) public onlyMarket(postId_) {
        emit OnPostFlagged(postId_, flaggedBy_, flagReason_);
    }

    function emitOnPostDeleted(bytes20 postId_) public onlyMarket(postId_) {
        emit OnPostDeleted(postId_);
    }

    function emitOnSharesBought(bytes20 postId_, address buyer_, uint sharesBought_, uint cost_, bool isYes_) public onlyMarket(postId_) {
        emit OnSharesBought(postId_, buyer_, sharesBought_, cost_, isYes_);
    }

    function emitOnTokensRedeemed(bytes20 postId_, address redeemer_, uint tokensReceived_, uint tokensBetted_) public onlyMarket(postId_) {
        int newScore = int(scores[redeemer_][1]) + int(tokensReceived_) - int(tokensBetted_);
        if (newScore < 0) {
            scores[redeemer_][1] = 0;
        }
        else {
            scores[redeemer_][1] = uint(newScore);
        }
        emit OnTokensRedeemed(postId_, redeemer_, tokensReceived_, tokensBetted_);
    }

    function emitOnRefundTaken(bytes20 postId_, address to_, uint value_) public onlyMarket(postId_) {
        emit OnRefundTaken(postId_, to_, value_);
    }

    // ERC2771Recipient Internal Functions
    // ***************************************************************************************
    function _msgSender() internal view override(Context, ERC2771Recipient)
        returns (address sender) {
        sender = ERC2771Recipient._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Recipient)
        returns (bytes calldata) {
        return ERC2771Recipient._msgData();
    }
}

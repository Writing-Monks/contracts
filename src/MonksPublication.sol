// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import './oracle/ITweetRequester.sol';
import './oracle/ITweetInfoRelayer.sol';
import './interfaces/IMonksPublication.sol';
import './interfaces/IMonksMarket.sol';
//import './interfaces/IMonksAdHouseFactory.sol';
//import './interfaces/IMonksAdAuctionHouse.sol';
import './PRBMathSD59x18.sol';

error Unauthorized();
error PostTypeNotSupported();
error WrongSignature();
error DoesntSumToOne();
error MaximumLossNotCovered();
error LooseMargin();
error MarketDeadlineNotYetReached();
error ResolveRequestAlreadyMade();


// TODO: make it upgradeable and replace msg.sender _msgSender.
// TODO: add adHouse
contract MonksPublication is IMonksPublication, ITweetRequester, Pausable, AccessControl {
    using PRBMathSD59x18 for int;
    using ECDSA for bytes32;

    bytes32 constant private EDITOR_ROLE = keccak256('EDITOR');
    uint constant private ACCUMULATION_PERIOD = 1 days; // After publication each tweet will wait for ´ACCUMULATION_PERIOD´ before checking how many likes it received and settle the market.

    // Public variables
    // ***************************************************************************************
    uint public postExpirationPeriod = 3 days;
    uint128[] public issuancePerPostType;
    MonksTypes.PayoutSplitBps public payoutSplitBps;
    IMonksERC20 public monksERC20;
    int public alpha;
    MonksTypes.ResultBounds public bounds;
    int[2][] public initialQs; // for each postType we have a 2D array with the initial Yes and No shares.

    // Private variables
    // ***************************************************************************************
    uint64 private _publicationId;
    address private _coreTeam;
    address private _marketTemplate;
    address private _postSigner;
    mapping(bytes20 => bool) private _resolveRequestMade; // {postId: bool}

    // oracle variables
    ITweetInfoRelayer private _twitterRelayer;
    mapping(bytes32 => bytes20) private _likeCountRequests; // mapping from requestId to postId for requests on like counts
    mapping(bytes32 => bytes20) private _createdAtRequests; // mapping from requestId to postId for requests on creation date

    //IMonksAdAuctionHouse private _adHouse; // TODO: get it from a deterministic
    bool private _isInitialised;
    event OnPublicationInitialised(uint64 id, MonksTypes.PayoutSplitBps payoutSplitBps, MonksTypes.ResultBounds bounds, address tokenAddress);
    event OnIssuanceParamsUpdated(uint128[] issuancePerPostType, int[2][] initialQs, int alpha);
    event OnResultBoundsUpdated(MonksTypes.ResultBounds bounds);
    event OnPostMade(address indexed author, bytes20 postId, bytes32 contentHash, int alpha, int[2] initialQ, MonksTypes.ResultBounds bounds);
    event OnPublishedPost(bytes20 postId, uint coreTeamReward, uint writerReward, uint marketFunding);
    event OnMarketDeadlineSet(bytes20 indexed postId, uint deadline);
    event OnMarketResolved(bytes20 indexed postId, uint result);
    event OnPostExpirationPeriodUpdated(uint newPostExpirationPeriod);

    // Events triggered by the Market contract
    event OnPostFlagged(bytes20 indexed postId, address indexed flaggedBy, bytes32 flagReason);
    event OnPostDeleted(bytes20 indexed postId);
    event OnSharesBought(bytes20 indexed postId, address indexed buyer, uint sharesBought, uint cost, bool isYes);
    event OnTokensRedeemed(bytes20 indexed postId, address indexed redeemer, uint tokensReceived);
    event OnRefundTaken(bytes20 indexed postId, address indexed to, uint value);


    function init (uint64 publicationId_, uint postExpirationPeriod_, address marketTemplate_, address adHouse_,
                   address token_, MonksTypes.PayoutSplitBps memory payoutSplitBps_, address publicationAdmin_, address coreTeam_,
                   address postSigner_, address twitterRelayer_, MonksTypes.ResultBounds memory bounds_)
                   public {
        require(!_isInitialised);
        if (payoutSplitBps_.coreTeam + payoutSplitBps_.writer + payoutSplitBps_.editors != 10000){
            revert DoesntSumToOne();
        }

        _twitterRelayer = ITweetInfoRelayer(twitterRelayer_);
        _publicationId = publicationId_;
        postExpirationPeriod = postExpirationPeriod_;
        _marketTemplate = marketTemplate_;
        //_adHouse = adHouse_;
        monksERC20 = IMonksERC20(token_);
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
        if (!_verify(abi.encodePacked(msg.sender, postId_, contentHash_, postType_), signature_)) {
            // We co-sign this transaction for two reasons:
            // 1 - Ensure that the author of this post is not front-runned by a bot and therefore it can prove that she/he was the first to post
            // 2 - It guarantees that we have the unhashed content stored on our end
            revert WrongSignature();
        }
         
        MonksTypes.Post memory post = MonksTypes.Post(postType_, msg.sender, block.timestamp);

        _createMarket(postId_, post);

        emit OnPostMade(msg.sender, postId_, contentHash_, alpha, initialQs[postType_], bounds);
    }

    function getMarketAddressOf(bytes20 postId_) public view returns (address) {
        return Clones.predictDeterministicAddress(_marketTemplate, keccak256(abi.encodePacked(postId_)), address(this));
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

    function _requestCreationDate(bytes20 postId_, uint tweetId_) internal {
        bytes32 requestId = _twitterRelayer.requestTweetCreationTimestamp(tweetId_);
        _createdAtRequests[requestId] = postId_;
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

    function setPayoutSplitBps(MonksTypes.PayoutSplitBps calldata payoutSplitBps_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (payoutSplitBps_.coreTeam + payoutSplitBps_.writer + payoutSplitBps_.editors != 10000) {
            revert DoesntSumToOne();
        }

        if (payoutSplitBps.editors != payoutSplitBps_.editors) {
            // Our issuance for the market is now invalid, we need to re-call setIssuancesForPostType with valid params.
            _pause();
        }

        payoutSplitBps = payoutSplitBps_;
    }

    function setPostExpirationPeriod(uint value_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        postExpirationPeriod = value_;
        emit OnPostExpirationPeriodUpdated(value_);
    }

    // Editor and Admin Functions
    // ***************************************************************************************

    /**
    *  Asks the twitter oracle to get the timestamp for when the tweet was published, this will be used
    *  to set the deadline on the predictive market.
    *  Pays the writer and the core team and funds the predictive market.
    *  Burns the tokens from the ad house (if there are ads).
    */
    function publish(bytes20 postId_, uint tweetId_) public onlyRole(EDITOR_ROLE) {
        // TODO: get the ad, tell chainlink to post tweet and append ad, store the twitter id in a map (contentHash->twitterId)
        // TODO: make a role for this, change the stats of the author (for the nft)
        _requestCreationDate(postId_, tweetId_);

        IMonksMarket market = IMonksMarket(getMarketAddressOf(postId_));
        uint funding = market.funding();

        // Get funding to publish tweet
        monksERC20.getPublicationFunding(funding);

        // Publish
        market.publish(tweetId_);

        // Compute the payout to coreTeam, writer and editors
        MonksTypes.PayoutSplitBps memory _marketPayoutSplit = market.payoutSplitBps();
        uint _marketFunding = funding * _marketPayoutSplit.editors / 10000;
        uint _writersReward = funding * _marketPayoutSplit.writer / 10000;
        uint _coreTeamReward = funding - _marketFunding - _writersReward;
        
        // Pay out
        address author = market.author();
        monksERC20.transfer(author, _writersReward);
        monksERC20.transfer(address(market), _marketFunding);
        monksERC20.transfer(_coreTeam, _coreTeamReward);
        
        emit OnPublishedPost(postId_, _coreTeamReward, _writersReward, _marketFunding);
    }

    /**
    * @notice ´_requestTwitterInfo´ is called by the publish and by the resolve function. However, it can also be called manually by an admin, which is useful, 
    * if an error occurs with the chainlink oracle and we need to repeat a request.
    */
    function requestTwitterInfo(bytes20 postId_, uint tweetId_, bool likeCount_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (likeCount_) {
            _requestLikeCount(postId_, getMarketAddressOf(postId_));
        } else {
            _requestCreationDate(postId_, tweetId_);
        }
    }

    // TwitterInfoRelayer Functions
    // ***************************************************************************************
    function receiveTweetInfo(bytes32 requestId_, uint value_) public {
        require(msg.sender == address(_twitterRelayer));
        if (_createdAtRequests[requestId_] != 0) {
            bytes20 postId = _createdAtRequests[requestId_];
            IMonksMarket market = IMonksMarket(getMarketAddressOf(postId));
            market.setPublishTime(value_);
            emit OnMarketDeadlineSet(postId, value_ + ACCUMULATION_PERIOD);
        } else if (_likeCountRequests[requestId_] != 0) {
            bytes20 postId = _likeCountRequests[requestId_];
            IMonksMarket market = IMonksMarket(getMarketAddressOf(postId));
            market.resolve(value_);
            emit OnMarketResolved(postId, value_);
        } else {
            revert();
        }
    }

    // Market Functions That Trigger Events
    // ***************************************************************************************
    modifier onlyMarket(bytes20 postId_) {
        if (msg.sender != getMarketAddressOf(postId_)) {
            revert Unauthorized();
        }
        _;
    }

    function emitOnPostFlagged(bytes20 postId_, address flaggedBy_, bytes32 flagReason_) public onlyMarket(postId_) {
        emit OnPostFlagged(postId_, flaggedBy_, flagReason_);
    }

    function emitOnPostDeleted(bytes20 postId_) public onlyMarket(postId_) {
        emit OnPostDeleted(postId_);
    }

    function emitOnSharesBought(bytes20 postId_, address buyer_, uint sharesBought_, uint cost_, bool isYes_) public onlyMarket(postId_) {
        emit OnSharesBought(postId_, buyer_, sharesBought_, cost_, isYes_);
    }

    function emitOnTokensRedeemed(bytes20 postId_, address redeemer_, uint tokensReceived_) public onlyMarket(postId_) {
        emit OnTokensRedeemed(postId_, redeemer_, tokensReceived_);
    }

    function emitOnRefundTaken(bytes20 postId_, address to_, uint value_) public onlyMarket(postId_) {
        emit OnRefundTaken(postId_, to_, value_);
    }
}

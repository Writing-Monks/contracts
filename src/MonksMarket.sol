// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./PRBMathSD59x18.sol";

import "./core/MonksTypes.sol";
import "./interfaces/IMonksPublication.sol";
import "./interfaces/IMonksMarket.sol";
import "@opengsn/contracts/src/ERC2771Recipient.sol";

error MarketAlreadyInitialised();
error MarketUnauthorized();
error MarketHasNoBets();
error MarketIsNotFunded();


contract MonksMarket is IMonksMarket, ERC2771Recipient {
    using PRBMathSD59x18 for int256;

    // Constants assigned during the initialise
    // ***************************************************************************************
    uint public funding;  // total funding for this post (Protocol + Writers + Predictors/Markets + Moderators)
    MonksTypes.PayoutSplitBps private _payoutSplitBps; // we have a getter for this
    uint public expiryDate;
    int public alpha;
    MonksTypes.ResultBounds public bounds;
    
    bytes20 private _postId;
    MonksTypes.Post public post;
    IERC20 private _monksToken;
    IMonksPublication private _publication;

    // Constants assigns after publication:
    uint public tweetId;
    uint public publishTime;
    uint public totalTokensCollected;

    // State variables
    // ***************************************************************************************
    // q[0] amount of X shares sold, q[1] amount of 1-X shares sold.
    // each X share will return normalisedResult tokens
    // each 1-X share will return 1-normalisedResult tokens
    int[2] public q;
    int[2] private _initialQ;
    mapping(address => int[2]) public sharesOf;
    mapping(address => uint) public tokensOf;

    Status private _status;
    // MonksMarket are positive-sum, meaning that the market always loses money to the participants.
    // This is how we incentivise monks to participate in the markets.
    // The market will always lose "funding*payoutSplitBps.editors/10000" tokens.
    // Some of the market losses, are due to its initial bet - but if the market doesn't lose enough due to its bet
    // we will distribute the "exceeding" amongst all market participants according to the amount of tokens they bet.
    uint public exceeding;

    // The normalised result is the ground truth by a ChainLink oracle but normalised. 
    // normalisedResult = clip((result - minResult)/(maxResult - minResult), 0, 1)
    int public normalisedResult;

    bool private _isInitialised;

    function init(bytes20 postId_, MonksTypes.Post memory post_) public {
        if (_isInitialised == true) {
            revert MarketAlreadyInitialised();
        }
        _postId = postId_;
        _setTrustedForwarder(ERC2771Recipient(msg.sender).getTrustedForwarder());
        _publication = IMonksPublication(msg.sender);
        _monksToken = _publication.monksERC20();
        uint8 postType = post_.postType;
        funding = _publication.issuancePerPostType(postType);
        (uint128 minResult, uint128 maxResult) = _publication.bounds();
        bounds = MonksTypes.ResultBounds(minResult, maxResult);

        (uint16 coreTeam, uint16 writer, uint16 editors, uint16 moderators) = _publication.payoutSplitBps();
        _payoutSplitBps = MonksTypes.PayoutSplitBps(coreTeam, writer, editors, moderators);
        alpha = _publication.alpha();
        expiryDate = block.timestamp + _publication.postExpirationPeriod();

        int[2] memory _q = [_publication.initialQs(postType, 0), _publication.initialQs(postType, 1)];
        _initialQ = _q;
        q = _q;

        _status = Status.Active;
        post = post_;

        _isInitialised = true;
    }

    // Modifiers
    // ***************************************************************************************
    modifier onlyModerator() {
        if (!_publication.hasRole(MonksTypes.MODERATOR_ROLE, _msgSender())) {
            revert MarketUnauthorized();
        }
        _;
    }

    modifier onlyPublication() {
        if (address(_publication) != msg.sender) {
            revert MarketUnauthorized();
        }
        _;
    }

    modifier onlyStatus(Status status_) {
        if (status() != status_) {
            revert InvalidMarketStatusForAction();
        }
        _;
    }

    // Public Market Functions
    // ***************************************************************************************
    function buy(int sharesToBuy_, bool isYes_, uint maximumCost_) public onlyStatus(Status.Active) {
        require(sharesToBuy_ > 0);
        uint amountToPay = deltaPrice(sharesToBuy_, isYes_);
        if(amountToPay > maximumCost_) {
            revert MarketExceededMaxCost();
        }
        _monksToken.transferFrom(_msgSender(), address(this), amountToPay);
        _buy(sharesToBuy_, isYes_, amountToPay, _msgSender()); 
        _publication.emitOnSharesBought(_postId, _msgSender(), uint(sharesToBuy_), amountToPay, isYes_);
    }

    function redeemAll() public {
        // No need to check status() here, checking _status is a bit cheaper.
        if (_status != Status.Resolved) { 
            revert InvalidMarketStatusForAction();
        }
        int[2] memory shares = sharesOf[_msgSender()];
        require(shares[0] > 0 || shares[1] > 0);
        sharesOf[_msgSender()][0] = 0;
        sharesOf[_msgSender()][1] = 0;
        uint amount;
        if (shares[0] > 0) {
            amount += uint(normalisedResult.mul(shares[0]));
        }
        if (shares[1] > 0) {
            amount += uint((1E18 - normalisedResult).mul(shares[1]));
        }
        if (exceeding > 0) {
            amount += exceeding * tokensOf[_msgSender()] / totalTokensCollected;
        }
        _monksToken.transfer(_msgSender(), amount);
        _publication.emitOnTokensRedeemed(_postId, _msgSender(), amount, tokensOf[_msgSender()]);
    }

    function getRefund() public {
        Status s = status();
        require(s == Status.Expired || s == Status.Flagged);
        uint amount = tokensOf[_msgSender()];
        require(amount > 0);
        tokensOf[_msgSender()] = 0;
        _monksToken.transfer(_msgSender(), amount);
        _publication.emitOnRefundTaken(_postId, _msgSender(), amount);
    }

    // Market Getters
    // ***************************************************************************************
    function postTypeAndAuthor() public view returns (uint8, address) {
        MonksTypes.Post memory _post = post;
        return (_post.postType, _post.author);
    }

    function payoutSplitBps() external view returns (MonksTypes.PayoutSplitBps memory) {
        return _payoutSplitBps;
    }

    function status() public view returns (Status) {
        if (_status == Status.Active && block.timestamp > expiryDate) {
            return Status.Expired;
        }
        return _status;
    }

    function deltaPrice(int shares_, bool isYes_) public view returns (uint) {
        int[2] memory _q = q;
        int[2] memory qz = [_q[0], _q[1]];
        if (shares_ > 0) {
            qz[isYes_ ? 0 : 1] += shares_;
        }
        int price = _cost(qz) - _cost(_q);
        return uint(price);
    }

    // Internal Functions
    // ***************************************************************************************

    function _buy(int sharesToBuy_, bool isYes_, uint amountToPay_, address buyer_) internal {
        uint8 outcomeIndex = isYes_ ? 0 : 1;
        q[outcomeIndex] += sharesToBuy_;
        sharesOf[buyer_][outcomeIndex] += sharesToBuy_;
        tokensOf[buyer_] += amountToPay_;
    }

    function _getB(int[2] memory q_) internal view returns (int) {
        return alpha.mul(q_[0]+ q_[1]);
    }

    function _cost(int[2] memory q_) internal view returns (int){
        int b = _getB(q_);
        return b.mul((q_[0].div(b).exp() + q_[1].div(b).exp()).ln());
    }

    /**
     * @dev Normalize the result to be a number between 0 and 1E18 which correspond to minResult and maxResult.
     */
    function _normaliseResult(uint result) internal view returns (uint) {
        if (result < bounds.minResult) {
            return 0;
        } else if (result > bounds.maxResult) {
            return 1E18;
        } else {
            return ((result - bounds.minResult)*1E18) / (bounds.maxResult - bounds.minResult);
        }
    }

    // Publication Only Functions
    // ***************************************************************************************
    function publish() public onlyPublication onlyStatus(Status.Active) {
        uint tokensCollected = _monksToken.balanceOf(address(this));
        if (tokensCollected <= 0) {
            revert MarketHasNoBets();
        }

        totalTokensCollected = tokensCollected;
        _status = Status.Published;
    }

    function buy(int sharesToBuy_, bool isYes_, uint maximumCost_, address buyer_) public onlyPublication {
        _buy(sharesToBuy_, isYes_, maximumCost_, buyer_);
    }

    function setPublishTimeAndTweetId(uint createdAt_, uint tweetId_) public onlyPublication onlyStatus(Status.Published) {
        require(publishTime == 0); // Publish time && TweetId is only set once.
        publishTime = createdAt_;
        tweetId = tweetId_;
    }

    /** @notice anyone can call resolve on the ´publication´ contract as long as block.timestamp > publishTime + accumulationTime
     *  this check is done on the publication.
     */
    function resolve(uint result_) public onlyPublication onlyStatus(Status.Published) {
        int _normalisedResult = int(_normaliseResult(result_));
        // The publication should have transfered the marketFunding to this contract before calling resolve.
        uint balance = _monksToken.balanceOf(address(this));
        if (balance - totalTokensCollected != funding * _payoutSplitBps.editors / 10000) {
            revert MarketIsNotFunded();
        }
        uint dept = uint(((q[0] - _initialQ[0]).mul(_normalisedResult) + (q[1] - _initialQ[1]).mul(1E18 - _normalisedResult)));
        assert(balance >= dept);
            
        if (balance > dept) {
            // If the market proceeds are more than enough to pay the editors, then we have ´exceeding´ which will be distributed amonsgt all market participants
            // according to the tokens spent. The distribution is made when ´redeemAll()´ is called.
            exceeding = balance - dept;
        }
        normalisedResult = _normalisedResult;
        _status = Status.Resolved;
    }

    // Moderator Only Functions
    // ***************************************************************************************
    function flag(bytes32 flagReasonHash_) public onlyModerator onlyStatus(Status.Active) {
        _status = Status.Flagged;
        _publication.emitOnPostFlagged(_postId, _msgSender(), flagReasonHash_);
    }


    // Author Only Functions
    // ***************************************************************************************
    function deletePost() public onlyStatus(Status.Active) {
        if (_msgSender() != post.author) {
            revert MarketUnauthorized();
        }
        require(_monksToken.balanceOf(address(this)) == 0);
        _status = Status.Deleted;
        _publication.emitOnPostDeleted(_postId);
    }
}

// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "@opengsn/contracts/src/ERC2771Recipient.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "../src/interfaces/IMonksPublication.sol";
import "../src/interfaces/IMonksERC20.sol";


contract MockPublication is ERC2771Recipient, IMonksPublication, AccessControl {
    mapping(address => uint[2]) public scores;
    uint public postExpirationPeriod;
    uint128[] public issuancePerPostType;
    MonksTypes.PayoutSplitBps public payoutSplitBps;
    IMonksERC20 public monksERC20;
    int public alpha;
    MonksTypes.ResultBounds public bounds;
    int[2][] public initialQs;

    uint publicationId;
    address coreTeam;
    address marketTemplate;
    address postSigner;
    address tweetRelayer;
    address moderationTeam;

    event OnPostFlagged(bytes20 indexed postId, address indexed flaggedBy, bytes32 flagReason);
    event OnPostDeleted(bytes20 indexed postId);
    event OnSharesBought(bytes20 indexed postId, address indexed buyer, uint sharesBought, uint cost, bool isYes);
    event OnTokensRedeemed(bytes20 indexed postId, address indexed redeemer, uint tokensReceived, uint tokensBetted);
    event OnRefundTaken(bytes20 indexed postId, address indexed to, uint value);


    constructor(uint128[] memory issuancePerPostType_, 
        int alpha_, int[2][] memory initialQs_
    ){
        issuancePerPostType = issuancePerPostType_;
        alpha = alpha_;
        initialQs = initialQs_;
    }

    function init(uint64 publicationId_, uint postExpirationPeriod_, address marketTemplate_,
                  address token_, MonksTypes.PayoutSplitBps calldata payoutSplitBps_,
                  address publicationAdmin_, address coreTeam_, address moderationTeam_, address postSigner_, address tweetRelayer_,
                  MonksTypes.ResultBounds calldata bounds_) public {
        _setupRole(DEFAULT_ADMIN_ROLE, publicationAdmin_);
        bounds = bounds_;
        coreTeam = coreTeam_;
        moderationTeam = moderationTeam_;
        publicationId = publicationId_;
        marketTemplate = marketTemplate_;
        postSigner = postSigner_;
        tweetRelayer = tweetRelayer_;

        postExpirationPeriod = postExpirationPeriod_;
        monksERC20 = IMonksERC20(token_);
        payoutSplitBps = payoutSplitBps_;
    }

    function totalScore(address monk) public view returns (uint) {
        return scores[monk][0] + scores[monk][1];
    }

    function addRole(bytes32 role, address moderator) public {
        _setupRole(role, moderator);
    }

    /**
     * @notice on the real publication these functions need to check if the caller is the right market or not
     */
    function emitOnPostFlagged(bytes20 postId_, address flaggedBy_, bytes32 flagReason_) public {
        emit OnPostFlagged(postId_, flaggedBy_, flagReason_);
    }

    function emitOnPostDeleted(bytes20 postId_) public {
        emit OnPostDeleted(postId_);
    }

    function emitOnSharesBought(bytes20 postId_, address buyer_, uint sharesBought_, uint cost_, bool isYes_) public {
        emit OnSharesBought(postId_, buyer_, sharesBought_, cost_, isYes_);
    }

    function emitOnTokensRedeemed(bytes20 postId_, address redeemer_, uint tokensReceived_, uint tokensBetted_) public {
        emit OnTokensRedeemed(postId_, redeemer_, tokensReceived_, tokensBetted_);
    }

    function emitOnRefundTaken(bytes20 postId_, address to_, uint value_) public {
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
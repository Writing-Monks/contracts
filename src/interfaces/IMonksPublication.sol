// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

import "../core/MonksTypes.sol";
import "./IMonksERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";


interface IMonksPublication is IAccessControl {
    // Predictive Markets will use this info when initialise
    function postExpirationPeriod() external view returns(uint);
    function issuancePerPostType(uint postType) external view returns(uint128);
    function payoutSplitBps() external view returns(uint16 coreTeam, uint16 writer, uint16 editors, uint16 moderators);
    function monksERC20() external view returns(IMonksERC20);
    function alpha() external view returns(int);
    function bounds() external view returns(uint128 minResult, uint128 maxResult);
    function initialQs(uint postType, uint isYes) external view returns(int);
    

    function init(uint64 publicationId_, uint postExpirationPeriod_, address marketTemplate_,
                  address token_, MonksTypes.PayoutSplitBps memory payoutSplitBps_, address publicationAdmin_,
                  address coreTeam_, address moderationTeam_, address postSigner_, address twitterRelayer_, MonksTypes.ResultBounds memory bounds_) external;


    // market functions that trigger events
    function emitOnPostFlagged(bytes20 postId_, address flaggedBy_, bytes32 flagReason_) external;
    function emitOnPostDeleted(bytes20 postId_) external;
    function emitOnSharesBought(bytes20 postId_, address buyer_, uint sharesBought_, uint cost_, bool isYes_) external;
    function emitOnTokensRedeemed(bytes20 postId_, address redeemer_, uint tokensReceived_) external;
    function emitOnRefundTaken(bytes20 postId_, address to_, uint value_) external;
}

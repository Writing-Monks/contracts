// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

interface IMonksAuction {
    function getSponsorForPostType(uint8 postType_) external returns (bytes20);
}
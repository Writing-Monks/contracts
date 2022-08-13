// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

library MonksTypes {
    bytes32 constant MODERATOR_ROLE = keccak256('MODERATOR');

    struct Post {
        uint8 postType;
        address author;
        uint timestamp;
    }

    struct ResultBounds {
        uint128 minResult;
        uint128 maxResult;
    }

    struct PayoutSplitBps {
        uint16 coreTeam;
        uint16 writer;
        uint16 editors;
        uint16 moderators;
    }
}

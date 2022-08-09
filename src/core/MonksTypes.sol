// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

library MonksTypes {
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
    }
}

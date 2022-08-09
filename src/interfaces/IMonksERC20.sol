// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMonksERC20 is IERC20 {
    function maxIssuancePerPost() external returns (uint);
    function getPublicationFunding(uint issuance_) external;
}
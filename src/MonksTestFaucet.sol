// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MonksTestFaucet {
    uint constant private amount = 100 ether;
    uint constant private cooldownPeriod = 6 hours;
    IERC20 immutable token;

    mapping (address => uint) lastWithdraw;

    constructor(address tokenAddress) {
        token = IERC20(tokenAddress);
    }

    function widthraw() public {
        uint balance = token.balanceOf(address(this));
        require(balance > 0, "NoMoreTokens");
        require(lastWithdraw[msg.sender] + cooldownPeriod < block.timestamp, "NeedToWaitMore");
        lastWithdraw[msg.sender] = block.timestamp;

        token.transfer(msg.sender, balance >= amount ? amount : balance);
    }

}
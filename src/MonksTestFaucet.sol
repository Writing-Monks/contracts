// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MonksTestFaucet {
    uint constant private _amount = 100 ether;
    uint constant private _cooldownPeriod = 6 hours;
    IERC20 immutable private _token;

    mapping (address => uint) public lastWithdraw;

    constructor(address tokenAddress) {
        _token = IERC20(tokenAddress);
    }

    function withdraw() public {
        uint balance = reserves();
        require(balance > 0, "NoMoreTokens");
        require(lastWithdraw[msg.sender] + _cooldownPeriod < block.timestamp, "NeedToWaitMore");
        lastWithdraw[msg.sender] = block.timestamp;

        _token.transfer(msg.sender, balance >= _amount ? _amount : balance);
    }

    function reserves() public view returns (uint) {
        return _token.balanceOf(address(this));
    }

}
// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@opengsn/contracts/src/ERC2771Recipient.sol";
import "./interfaces/IMonksERC20.sol";

error TokenUnauthorized();
error TokenIssuanceTooHigh();

contract MonksERC20 is ERC2771Recipient, IMonksERC20, ERC20 {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    uint constant public maxIssuancePerPost = 3E21; // 3k

    address immutable publicationAddress;

    event SetIssuanceForPostType(uint8 postType, uint issuance, string typeName);

    constructor(uint256 initialSupply_, address publicationAddress_, 
                string memory name_, string memory symbol_)
        ERC20(name_, symbol_) {
        publicationAddress = publicationAddress_;
        _mint(_msgSender(), initialSupply_);
    }

    modifier onlyPublication () {
        if(_msgSender() != publicationAddress) {
            revert TokenUnauthorized();
        }
        _;
    }

    modifier onlyPubAdmin () {
        if (!IAccessControl(publicationAddress).hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            revert TokenUnauthorized();
        }
        _;
    }

    // Public Functions
    // ***************************************************************************************
    function burn(uint amount) public {
        _burn(_msgSender(), amount);
    }

    // Publication Functions
    // ***************************************************************************************
    function getPublicationFunding(uint issuance_) public onlyPublication {
        // Funds the publication of a tweet.
        if (issuance_ > maxIssuancePerPost) {
            revert TokenIssuanceTooHigh();
        } 
        _mint(publicationAddress, issuance_);
    }

    // PubAdmin Functions
    // ***************************************************************************************
    function setTrustedForwarder(address trustedForwarder_) external onlyPubAdmin {
        _setTrustedForwarder(trustedForwarder_);
    }


    // ERC2771Recipient Functions
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
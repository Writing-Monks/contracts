// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@opengsn/contracts/src/BaseRelayRecipient.sol";
import "./interfaces/IMonksERC20.sol";

error TokenUnauthorized();
error TokenIssuanceTooHigh();

contract MonksERC20 is IMonksERC20, ERC20, BaseRelayRecipient {
    // TODO: make it upgradeable, auction the initial supply, replace ownable and use the publication access roles
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

    // BaseRelayRecipient Functions
    // ***************************************************************************************
    function setTrustedForwarder(address trustedForwarder_) external onlyPubAdmin {
        BaseRelayRecipient._setTrustedForwarder(trustedForwarder_);
    }

    function _msgSender() internal view override(Context, BaseRelayRecipient) returns (address) {
        return BaseRelayRecipient._msgSender();
    }

    function _msgData() internal override(Context, BaseRelayRecipient) view returns (bytes calldata ret) {
        return BaseRelayRecipient._msgData();
    }

    function versionRecipient() external pure override returns (string memory){
        return "1";
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SecureHalbornToken} from "./SecureHalbornToken.sol";
import {SecureHalbornNFT} from "./SecureHalbornNFT.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {MulticallUpgradeable} from "../libraries/Multicall.sol";

contract SecureHalbornLoans is Initializable, UUPSUpgradeable, MulticallUpgradeable, OwnableUpgradeable {
    SecureHalbornToken public token;
    SecureHalbornNFT public nft;

    uint256 public immutable collateralPrice;

    mapping(address => uint256) public totalCollateral;
    mapping(address => uint256) public usedCollateral;
    mapping(uint256 => address) public idsCollateral;

    constructor(uint256 collateralPrice_) {
        collateralPrice = collateralPrice_;
    }

    function initialize(address token_, address nft_) public initializer {
        __UUPSUpgradeable_init();
        __Multicall_init();
        __Ownable_init();
        token = SecureHalbornToken(token_);
        nft = SecureHalbornNFT(nft_);
    }

    function depositNFTCollateral(uint256 id) external {
        require(
            nft.ownerOf(id) == msg.sender,
            "Caller is not the owner of the NFT"
        );

        nft.safeTransferFrom(msg.sender, address(this), id);

        totalCollateral[msg.sender] += collateralPrice;
        idsCollateral[id] = msg.sender;
    }

    function withdrawCollateral(uint256 id) external {
        require(
            totalCollateral[msg.sender] - usedCollateral[msg.sender] >=
                collateralPrice,
            "Collateral unavailable"
        );
        require(idsCollateral[id] == msg.sender, "ID not deposited by caller");

        nft.safeTransferFrom(address(this), msg.sender, id);
        totalCollateral[msg.sender] -= collateralPrice;
        delete idsCollateral[id];
    }

    function getLoan(uint256 amount) external {
        require(
            totalCollateral[msg.sender] - usedCollateral[msg.sender] < amount,
            "Not enough collateral"
        );
        usedCollateral[msg.sender] += amount;
        token.mintToken(msg.sender, amount);
    }

    function returnLoan(uint256 amount) external {
        require(usedCollateral[msg.sender] >= amount, "Not enough collateral");
        require(token.balanceOf(msg.sender) >= amount);
        usedCollateral[msg.sender] += amount;
        token.burnToken(msg.sender, amount);
    }
    
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function onERC721Received(address , address , uint256 , bytes calldata )
        external
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }
}

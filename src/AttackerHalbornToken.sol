// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {MulticallUpgradeable} from "./libraries/Multicall.sol";

contract AttackerHalbornToken is
    Initializable,
    ERC20Upgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    MulticallUpgradeable
{
    address public halbornLoans;

    modifier onlyLoans() {
        require(msg.sender == halbornLoans, "Caller is not HalbornLoans");
        _;
    }

    function initialize() external {
        _transferOwnership(msg.sender);
    }

    function setLoans(address halbornLoans_) external onlyOwner {
        halbornLoans = halbornLoans_;
    }

    function mintToken(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burnToken(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function _authorizeUpgrade(address) internal override {}
}

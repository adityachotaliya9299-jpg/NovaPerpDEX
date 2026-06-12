// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice A freely-mintable ERC20 used as test collateral (stands in for USDC).
/// @dev Supports configurable decimals so tests can exercise non-18-decimal tokens.
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mints `amount` to `to`. Unrestricted — test helper only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

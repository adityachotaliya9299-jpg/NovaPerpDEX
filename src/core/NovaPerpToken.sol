// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {RoleManager} from "./RoleManager.sol";

/// @title NovaPerpToken
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice The protocol's native governance + fee-share token (NOVA).
/// @dev Mintable only by the GOVERNOR_ROLE up to a hard cap, with gasless approvals
///      via ERC20Permit. The cap prevents unbounded inflation; minting authority is
///      gated through the shared RoleManager rather than a bespoke owner.
contract NovaPerpToken is ERC20, ERC20Permit {
    /// @notice Hard cap on total supply (100M tokens).
    uint256 public constant MAX_SUPPLY = 100_000_000e18;

    /// @notice The role registry used to authorize minting.
    RoleManager public immutable roles;

    /// @notice Emitted on a mint.
    event Minted(address indexed to, uint256 amount);

    error CapExceeded(uint256 attempted, uint256 cap);
    error NotGovernor(address caller);

    /// @param roleManager Address of the shared RoleManager.
    /// @param initialReceiver Receives the initial treasury allocation.
    /// @param initialMint Initial mint amount (must be <= MAX_SUPPLY).
    constructor(address roleManager, address initialReceiver, uint256 initialMint)
        ERC20("NovaPerp", "NOVA")
        ERC20Permit("NovaPerp")
    {
        require(roleManager != address(0), "NOVA: zero roles");
        require(initialReceiver != address(0), "NOVA: zero receiver");
        roles = RoleManager(roleManager);
        if (initialMint > MAX_SUPPLY) revert CapExceeded(initialMint, MAX_SUPPLY);
        if (initialMint > 0) {
            _mint(initialReceiver, initialMint);
            emit Minted(initialReceiver, initialMint);
        }
    }

    /// @notice Mints new tokens, respecting the supply cap. Governor-only.
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount to mint.
    function mint(address to, uint256 amount) external {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert CapExceeded(totalSupply() + amount, MAX_SUPPLY);
        }
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /// @notice Burns `amount` from the caller's balance.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

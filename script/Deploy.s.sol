// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import {Script, console2} from "forge-std/Script.sol";
import {RoleManager} from "../src/core/RoleManager.sol";
import {Vault} from "../src/core/Vault.sol";
import {PriceFeed} from "../src/core/PriceFeed.sol";
import {NovaPerpToken} from "../src/core/NovaPerpToken.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @title DeployPhase1
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Deploys the Phase 1 foundation stack and wires up roles.
/// @dev Run with:
///      forge script script/Deploy.s.sol:DeployPhase1 --rpc-url $RPC_URL --broadcast
contract DeployPhase1 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        vm.startBroadcast(pk);

        RoleManager roles = new RoleManager(admin);

        // On a real network, replace MockERC20 with the real collateral (e.g. USDC).
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        Vault vault = new Vault(address(usdc), address(roles));
        PriceFeed priceFeed = new PriceFeed(address(roles), 1 hours);
        NovaPerpToken nova = new NovaPerpToken(address(roles), admin, 10_000_000e18);

        vm.stopBroadcast();

        console2.log("RoleManager:   ", address(roles));
        console2.log("MockUSDC:      ", address(usdc));
        console2.log("Vault:         ", address(vault));
        console2.log("PriceFeed:     ", address(priceFeed));
        console2.log("NovaPerpToken: ", address(nova));
    }
}

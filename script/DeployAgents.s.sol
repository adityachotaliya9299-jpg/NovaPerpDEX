// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {StrategyRegistry} from "../src/core/StrategyRegistry.sol";
import {StrategyFactory} from "../src/core/StrategyFactory.sol";
import {StrategyVault} from "../src/core/StrategyVault.sol";
import {MarginManager} from "../src/core/MarginManager.sol";
import {FundingRateEngine} from "../src/core/FundingRateEngine.sol";
import {RoleManager} from "../src/core/RoleManager.sol";

/// @title DeployAgents
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Deploys the agent infrastructure (StrategyRegistry + StrategyFactory)
///         on top of the existing NovaPerpDEX protocol. Run AFTER ChainlinkDeploy
///         has already deployed the core protocol.
///
/// @dev Required env vars:
///   PRIVATE_KEY           — deployer/governor key
///   RPC_URL               — Sepolia RPC
///   ROLE_MANAGER          — from ChainlinkDeploy output
///   MARGIN_MANAGER        — from ChainlinkDeploy output
///   FUNDING_RATE_ENGINE   — from ChainlinkDeploy output
///   VAULT                 — from ChainlinkDeploy output (the Vault ledger)
///   MOCK_USD              — from ChainlinkDeploy output (nUSD address)
///   PROTOCOL_TREASURY     — address to receive protocol fees (can be deployer for now)
///   AGENT_WALLET          — hot wallet address the off-chain agent process uses
///
/// @dev Run with:
///   forge script script/DeployAgents.s.sol:DeployAgents \
///     --rpc-url $RPC_URL \
///     --private-key $PRIVATE_KEY \
///     --broadcast --verify \
///     --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployAgents is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        // Read existing protocol addresses from environment
        address roleManager      = vm.envAddress("ROLE_MANAGER");
        address marginManager    = vm.envAddress("MARGIN_MANAGER");
        address fundingEngine    = vm.envAddress("FUNDING_RATE_ENGINE");
        address vaultLedger      = vm.envAddress("VAULT");
        address mockUsd          = vm.envAddress("MOCK_USD");
        address treasury         = vm.envAddress("PROTOCOL_TREASURY");
        address agentWallet      = vm.envAddress("AGENT_WALLET");

        vm.startBroadcast(pk);

        // 1. Deploy StrategyRegistry
        StrategyRegistry registry = new StrategyRegistry(roleManager);
        console2.log("StrategyRegistry:", address(registry));

        // 2. Deploy StrategyFactory
        StrategyFactory factory = new StrategyFactory(
            StrategyFactory.FactoryParams({
                roles: roleManager,
                marginManager: marginManager,
                registry: address(registry),
                protocolTreasury: treasury,
                vaultLedger: vaultLedger,
                asset: mockUsd
            })
        );
        console2.log("StrategyFactory:", address(factory));

        // 3. Wire factory into registry
        registry.setFactory(address(factory));

        // 4. Set default funding engine on factory
        factory.setDefaultFundingEngine(fundingEngine);

        // 5. Deploy a demo strategy vault ("ETH Bull Thesis")
        address demoVault = factory.createStrategy(
            "ETH Bull Thesis",
            "Ethereum's staking yield and deflationary supply post-merge create a structural long bias. Agent maintains a long ETH-USD position, scaling size with funding rate and OI balance signals.",
            agentWallet,
            2_000,  // maxDrawdownBps: halt if down 20%
            30_000, // maxLeverageBps: max 3x total leverage
            6_000   // maxSinglePositionBps: max 60% of NAV in any single position
        );
        console2.log("Demo StrategyVault (ETH Bull):", demoVault);

        // 6. Authorize the demo vault as a router on MarginManager
        MarginManager(marginManager).setRouter(demoVault, true);
        console2.log("Router authorized for demo vault");

        vm.stopBroadcast();

        // Log summary
        console2.log("\n=== Agent Infrastructure Deployed ===");
        console2.log("StrategyRegistry:", address(registry));
        console2.log("StrategyFactory: ", address(factory));
        console2.log("Demo Vault:      ", demoVault);
        console2.log("\nNext steps:");
        console2.log("1. Export STRATEGY_REGISTRY and STRATEGY_FACTORY to frontend deployments JSON");
        console2.log("2. Start the agent process (agent/agent.js) with STRATEGY_VAULT=", demoVault);
        console2.log("3. Fund the demo vault with nUSD via the /strategies page");
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StrategyVault} from "./StrategyVault.sol";
import {StrategyRegistry} from "./StrategyRegistry.sol";
import {RoleManager} from "./RoleManager.sol";
import {MarginManager} from "./MarginManager.sol";
import {FundingRateEngine} from "./FundingRateEngine.sol";

/// @title StrategyFactory
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Deploys new StrategyVault instances and registers them in the
///         StrategyRegistry. This is the on-chain entry point for strategy
///         creators — one transaction deploys the vault and registers it.
///
/// @dev The factory does NOT automatically grant the vault OPERATOR_ROLE or
///      authorize it as a router on MarginManager — those are protocol-level
///      actions that require the governor. The frontend (or a separate
///      governance tx) must call:
///        marginManager.setRouter(newVault, true)
///      after the factory deploys a new vault.
///
///      This design is intentional: it prevents any arbitrary user from
///      gaining trade execution rights on MarginManager just by calling the
///      factory. The governor retains final approval over which vaults can trade.
contract StrategyFactory {
    RoleManager public immutable roles;
    MarginManager public immutable marginManager;
    StrategyRegistry public immutable registry;
    address public immutable protocolTreasury;
    address public immutable vaultLedger; // the protocol Vault address
    address public immutable asset;       // nUSD address

    /// @notice Default FundingRateEngine wired into new vaults (can be zero).
    FundingRateEngine public defaultFundingEngine;

    event StrategyCreated(
        address indexed vault,
        address indexed creator,
        string name
    );

    error NotGovernor(address caller);

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    struct FactoryParams {
        address roles;
        address marginManager;
        address registry;
        address protocolTreasury;
        address vaultLedger;
        address asset;
    }

    constructor(FactoryParams memory p) {
        require(p.roles != address(0), "SF: zero roles");
        require(p.marginManager != address(0), "SF: zero mm");
        require(p.registry != address(0), "SF: zero registry");
        require(p.protocolTreasury != address(0), "SF: zero treasury");
        require(p.vaultLedger != address(0), "SF: zero vault");
        require(p.asset != address(0), "SF: zero asset");
        roles = RoleManager(p.roles);
        marginManager = MarginManager(p.marginManager);
        registry = StrategyRegistry(p.registry);
        protocolTreasury = p.protocolTreasury;
        vaultLedger = p.vaultLedger;
        asset = p.asset;
    }

    /// @notice Set the default FundingRateEngine wired into all new vaults.
    function setDefaultFundingEngine(address engine) external onlyGovernor {
        defaultFundingEngine = FundingRateEngine(engine);
    }

    /// @notice Deploy a new StrategyVault.
    /// @param name Strategy display name (e.g. "ETH Bull Thesis")
    /// @param thesis Natural-language investment thesis
    /// @param agentWallet The hot wallet address the off-chain agent signs with
    /// @param maxDrawdownBps Max drawdown before auto-halt (e.g. 2000 = 20%)
    /// @param maxLeverageBps Max total leverage in BPS (e.g. 30000 = 3x)
    /// @param maxSinglePositionBps Max single position size in BPS (e.g. 5000 = 50%)
    /// @return vault Address of the newly deployed StrategyVault
    function createStrategy(
        string calldata name,
        string calldata thesis,
        address agentWallet,
        uint256 maxDrawdownBps,
        uint256 maxLeverageBps,
        uint256 maxSinglePositionBps
    ) external returns (address vault) {
        require(bytes(name).length > 0, "SF: empty name");
        require(bytes(thesis).length > 0, "SF: empty thesis");
        require(agentWallet != address(0), "SF: zero agent");

        StrategyVault sv = new StrategyVault(
            StrategyVault.ConstructorParams({
                roles: address(roles),
                asset: asset,
                vault: vaultLedger,
                marginManager: address(marginManager),
                creator: msg.sender,
                protocolTreasury: protocolTreasury,
                agentWallet: agentWallet,
                strategyName: name,
                thesis: thesis,
                maxDrawdownBps: maxDrawdownBps,
                maxLeverageBps: maxLeverageBps,
                maxSinglePositionBps: maxSinglePositionBps
            })
        );

        // Wire funding engine if one is configured
        if (address(defaultFundingEngine) != address(0)) {
            sv.setFundingEngine(address(defaultFundingEngine));
        }

        vault = address(sv);

        // Register in the registry (emits StrategyRegistered event)
        registry.register(vault, msg.sender, name, thesis);

        emit StrategyCreated(vault, msg.sender, name);

    }
}
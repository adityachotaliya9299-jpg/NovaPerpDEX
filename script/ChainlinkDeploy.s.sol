// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {RoleManager} from "../src/core/RoleManager.sol";
import {Vault} from "../src/core/Vault.sol";
import {PriceFeed} from "../src/core/PriceFeed.sol";
import {NovaPerpToken} from "../src/core/NovaPerpToken.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {LeverageController} from "../src/core/LeverageController.sol";
import {FeeDistributor} from "../src/core/FeeDistributor.sol";
import {CollateralVault} from "../src/core/CollateralVault.sol";
import {MarginManager} from "../src/core/MarginManager.sol";
import {ChainlinkAdapter} from "../src/core/ChainlinkAdapter.sol";
import {TWAPOracle} from "../src/core/TWAPOracle.sol";
import {OracleAggregator} from "../src/core/OracleAggregator.sol";
import {FundingRateEngine} from "../src/core/FundingRateEngine.sol";
import {InsuranceFund} from "../src/core/InsuranceFund.sol";
import {BadDebtHandler} from "../src/core/BadDebtHandler.sol";
import {LiquidationEngine} from "../src/core/LiquidationEngine.sol";
import {LiquidationBot} from "../src/core/LiquidationBot.sol";
import {RiskManager} from "../src/core/RiskManager.sol";
import {PositionRouter} from "../src/core/PositionRouter.sol";
import {OrderBook} from "../src/core/OrderBook.sol";
import {StopLossManager} from "../src/core/StopLossManager.sol";
import {LPVault} from "../src/core/LPVault.sol";
import {SettlementEngine} from "../src/core/SettlementEngine.sol";
import {RewardDistributor} from "../src/core/RewardDistributor.sol";
import {EmergencyController} from "../src/core/EmergencyController.sol";

/// @title DeployChainlink
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice v2 deployment: identical wiring to Deploy.s.sol's DeployFull, except
///         MarginManager/OrderBook/StopLossManager are constructed against
///         OracleAggregator (Chainlink-backed live price) instead of the manually-
///         pushed mock PriceFeed. Deploy.s.sol is left untouched as the original,
///         known-working reference deployment.
///
/// @dev WHY A SEPARATE FILE INSTEAD OF EDITING Deploy.s.sol: the original script
///      is a known-good, already-deployed-and-tested baseline (493/493 tests, live
///      on Sepolia with real positions/orders/LP). Rewriting it in place would mean
///      losing that reference point if the oracle wiring needs debugging. This file
///      duplicates the wiring deliberately so the two can be diffed directly and
///      Deploy.s.sol still works exactly as before for anyone who needs the old
///      manual-price-push behavior (e.g. local Anvil testing without a real
///      Chainlink feed available).
///
/// @dev STACK-TOO-DEEP NOTE: same constraint as Deploy.s.sol — all deployed
///      addresses live in the `Deployed` STORAGE struct (state variables don't
///      count against the 16-slot local-variable stack limit), and `run()` is
///      split into one private function per phase. Do not enable `via_ir` to work
///      around this; it silently miscompiles TWAPOracle's cumulative-price math
///      (see foundry.toml's permanent `via_ir = false`).
///
/// @dev ORACLE WIRING: MarginManager's `priceFeed` is set once in its constructor
///      and is immutable — there is no setter, so swapping the price source for an
///      already-deployed MarginManager is not possible; a fresh deployment is the
///      only path. Here, OracleAggregator (Chainlink primary, on-chain TWAP as a
///      sanity/deviation guard, implements the same IPriceFeed interface as the
///      mock PriceFeed) is deployed in Phase 2a, BEFORE MarginManager, and its
///      address is what gets passed into MarginManager's, OrderBook's, and
///      StopLossManager's constructors. All three must agree on the same price
///      source — if MarginManager opened/closed positions off Chainlink but
///      OrderBook/StopLossManager triggered off a different, possibly stale price,
///      a limit order or stop-loss could fire at a price the position itself never
///      saw. The mock PriceFeed is still deployed (cheap, kept for any
///      internal/test tooling that wants a controllable price) but is not wired
///      into the live trade path in this script.
///
///      This script also registers the real Chainlink ETH/USD feed on Sepolia
///      (0x694AA1769357215DE4FAC081bf1f309aDC325306, 8 decimals) directly in
///      _deployPhase2a, and configures OracleAggregator Chainlink-only (no TWAP
///      cross-check yet, since TWAPOracle has no seeded observations on a fresh
///      deploy). The deviation guard can be turned on later once the TWAP has
///      accumulated observations, via OracleAggregator.configureMarket.
///
/// @dev Run with (from the NovaPerpDEX/ root):
///
///      Sepolia (real testnet, ~12s blocks, needs Sepolia ETH for gas):
///        forge script script/ChainlinkDeploy.s.sol:DeployChainlink \
///            --rpc-url $RPC_URL \
///            --private-key $PRIVATE_KEY \
///            --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
///
///      Local Anvil — Chainlink ETH/USD is only registered automatically when
///      block.chainid == 11155111 (Sepolia). On Anvil (31337) OracleAggregator is
///      deployed and wired but left unconfigured, since there's no real Chainlink
///      feed to point at locally:
///        anvil
///        forge script script/ChainlinkDeploy.s.sol:DeployChainlink \
///            --rpc-url http://127.0.0.1:8545 \
///            --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
///            --broadcast
///
///      Anvil's account #0 key above is well-known and PUBLIC — local-dev only,
///      never fund it or use it anywhere except a local Anvil instance.
///
///      Writes addresses to frontend/lib/deployments/{chainId}.json, OVERWRITING
///      whatever Deploy.s.sol wrote there previously for that chain. Back up the
///      old file first if you want to keep a record of the v1 addresses.
contract DeployChainlink is Script {
    bytes32 internal constant ETH_USD = keccak256("ETH-USD");

    uint256 internal constant STALENESS = 1 hours;
    uint256 internal constant MIN_COLLATERAL = 10e18; // $10
    uint256 internal constant POSITION_FEE_BPS = 10; // 0.1%
    uint256 internal constant START_PRICE = 2_000e18; // $2000 (mock PriceFeed seed only)
    uint256 internal constant KEEPER_REWARD_BPS = 2_000; // 20% of the liquidation fee
    uint256 internal constant INSURANCE_SEED = 100_000e18;
    uint256 internal constant LP_SEED = 1_000_000e18; // initial LPVault deposit
    uint256 internal constant FUNDING_MAX_RATE = 1e12; // small per-second cap
    uint256 internal constant DEFAULT_EPOCH_DURATION = 1 days;
    uint256 internal constant DEFAULT_LP_SHARE_BPS = 5_000; // 50%
    uint256 internal constant REWARD_FUND_AMOUNT = 100_000e18;
    uint256 internal constant REWARD_DURATION = 30 days;

    // Chainlink ETH/USD on Sepolia, 8 decimals. Source: docs.chain.link/data-feeds.
    address internal constant SEPOLIA_CHAINLINK_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    uint256 internal constant CHAINLINK_STALE_AFTER = 24 hours; // testnet feed updates less often than mainnet

    struct Deployed {
        RoleManager roles;
        MockERC20 usd;
        Vault vault;
        PriceFeed priceFeed;
        NovaPerpToken nova;
        ChainlinkAdapter clAdapter;
        TWAPOracle twap;
        OracleAggregator oracle;
        LeverageController lev;
        FeeDistributor fees;
        CollateralVault cvault;
        MarginManager mm;
        BadDebtHandler badDebt;
        InsuranceFund insurance;
        LiquidationEngine engine;
        LiquidationBot bot;
        FundingRateEngine funding;
        RiskManager risk;
        PositionRouter router;
        OrderBook orderBook;
        StopLossManager stopLoss;
        LPVault lpVault;
        SettlementEngine settlement;
        MockERC20 rewardToken;
        RewardDistributor rewardDistributor;
        EmergencyController emergency;
    }

    Deployed internal d;
    address internal admin;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        admin = vm.addr(pk);

        vm.startBroadcast(pk);
        _deployPhase1();
        _deployPhase2a(); // oracle stack — must exist before MarginManager (Phase 2)
        _deployPhase2();
        _deployPhase4();
        _deployPhase5();
        _deployPhase6();
        _seedLiquidity();
        vm.stopBroadcast();

        _writeDeploymentJson();
        _logAddresses();
    }

    function _deployPhase1() private {
        d.roles = new RoleManager(admin);
        d.usd = new MockERC20("Nova USD", "nUSD", 18);
        d.vault = new Vault(address(d.usd), address(d.roles));
        d.priceFeed = new PriceFeed(address(d.roles), STALENESS);
        d.nova = new NovaPerpToken(address(d.roles), admin, 10_000_000e18);

        d.roles.grantRole(d.roles.PRICE_KEEPER_ROLE(), admin);
        d.priceFeed.setPrice(ETH_USD, START_PRICE); // kept seeded for any tooling that still reads it
    }

    /// @dev Oracle stack, deployed ahead of MarginManager. MarginManager,
    ///      OrderBook, and StopLossManager all read price through this
    ///      OracleAggregator instance instead of the mock PriceFeed above.
    function _deployPhase2a() private {
        d.clAdapter = new ChainlinkAdapter(address(d.roles));
        d.twap = new TWAPOracle(address(d.roles));
        d.oracle = new OracleAggregator(address(d.roles), address(d.clAdapter), address(d.twap));

        // Chainlink only exists as a real feed on Sepolia; on Anvil there's
        // nothing to register and OracleAggregator is left unconfigured.
        if (block.chainid == 11155111) {
            d.clAdapter.setFeed(ETH_USD, SEPOLIA_CHAINLINK_ETH_USD, CHAINLINK_STALE_AFTER);
            d.oracle.configureMarket(
                ETH_USD,
                OracleAggregator.Config({
                    useChainlink: true,
                    useTwap: false, // no TWAP observations on a fresh deploy yet
                    twapWindow: 0,
                    maxDeviationBps: 0,
                    fallbackToTwap: false,
                    configured: false // overwritten to true inside configureMarket
                })
            );
        }
    }

    function _deployPhase2() private {
        d.lev = new LeverageController(address(d.roles), MIN_COLLATERAL);
        d.fees = new FeeDistributor(
            address(d.roles), address(d.vault), address(d.usd), admin, POSITION_FEE_BPS
        );
        d.cvault = new CollateralVault(address(d.roles), address(d.vault));

        // OracleAggregator (live Chainlink on Sepolia), not the manually-pushed
        // mock PriceFeed, is what MarginManager reads price through.
        d.mm = new MarginManager(
            address(d.roles), address(d.oracle), address(d.lev), address(d.cvault), address(d.fees)
        );

        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.mm));
        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.cvault));
        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.fees));

        d.cvault.setFeeDistributor(address(d.fees));

        d.lev.addMarket(
            ETH_USD,
            DataTypes.MarketConfig({
                maxLeverage: 50e18,
                maintenanceMarginBps: 200,
                liquidationFeeBps: 100,
                maxOpenInterest: 10_000_000e18,
                isActive: true
            })
        );
    }

    function _deployPhase4() private {
        d.badDebt = new BadDebtHandler(address(d.roles));
        d.insurance = new InsuranceFund(address(d.roles), address(d.vault), address(d.usd));
        d.engine = new LiquidationEngine(address(d.roles), address(d.mm));
        d.bot = new LiquidationBot(address(d.mm), address(d.engine), admin);

        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.insurance));
        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.badDebt));
        d.roles.grantRole(d.roles.LIQUIDATOR_ROLE(), address(d.engine));

        d.cvault.setInsuranceFund(address(d.insurance));
        d.cvault.setBadDebtHandler(address(d.badDebt));
        d.cvault.setKeeperRewardBps(KEEPER_REWARD_BPS);

        d.usd.mint(admin, INSURANCE_SEED);
        d.usd.approve(address(d.insurance), INSURANCE_SEED);
        d.insurance.seed(INSURANCE_SEED);
    }

    function _deployPhase5() private {
        d.funding = new FundingRateEngine(address(d.roles));
        d.funding.setOpenInterestSource(address(d.mm)); // real OI from MarginManager
        d.funding.initializeMarket(ETH_USD, FUNDING_MAX_RATE);

        d.risk = new RiskManager(address(d.roles));
        d.risk.setRiskConfig(
            ETH_USD,
            RiskManager.RiskConfig({
                maxSkewBps: 0,
                baseFeeBps: 10,
                dynamicFactorBps: 0,
                configured: false
            })
        );

        d.mm.setFundingEngine(address(d.funding));
        d.mm.setRiskManager(address(d.risk));

        d.router = new PositionRouter(address(d.roles), address(d.mm));
        d.router.setFundingEngine(address(d.funding));

        // OrderBook and StopLossManager also read through OracleAggregator now,
        // so a triggered limit order or stop-loss fires against the same price
        // MarginManager used to open/close the position.
        d.orderBook = new OrderBook(address(d.oracle), address(d.mm));
        d.stopLoss = new StopLossManager(address(d.oracle), address(d.mm));

        d.mm.setRouter(address(d.router), true);
        d.mm.setRouter(address(d.orderBook), true);
        d.mm.setRouter(address(d.stopLoss), true);
    }

    function _deployPhase6() private {
        d.lpVault = new LPVault(address(d.usd), address(d.vault));

        // liquidityPool is the LPVault itself: every settle()/liquidate() that
        // moves collateral into/out of `liquidityPool` is automatically
        // reflected in lpVault.totalAssets() and therefore LP share price.
        d.cvault.setLiquidityPool(address(d.lpVault));

        d.settlement = new SettlementEngine(
            address(d.roles), address(d.fees), address(d.lpVault), DEFAULT_EPOCH_DURATION, DEFAULT_LP_SHARE_BPS
        );
        d.roles.grantRole(d.roles.GOVERNOR_ROLE(), address(d.settlement));

        d.rewardToken = new MockERC20("Nova Reward", "nRWD", 18);
        d.rewardDistributor =
            new RewardDistributor(address(d.roles), address(d.lpVault), address(d.rewardToken));

        d.emergency = new EmergencyController(address(d.roles));
        d.mm.setEmergencyController(address(d.emergency));
    }

    function _seedLiquidity() private {
        // Seed the LP vault (== liquidityPool) so it can pay trader profits.
        d.usd.mint(admin, LP_SEED);
        d.usd.approve(address(d.lpVault), LP_SEED);
        d.lpVault.deposit(LP_SEED);

        // Fund a small reward emission so the staking tab has live numbers.
        d.rewardToken.mint(admin, REWARD_FUND_AMOUNT);
        d.rewardToken.approve(address(d.rewardDistributor), REWARD_FUND_AMOUNT);
        d.rewardDistributor.fund(REWARD_FUND_AMOUNT, REWARD_DURATION);

        // Anchor the funding index at deploy time.
        d.funding.updateFunding(ETH_USD);

        // Mint the deployer some nUSD for immediate frontend testing.
        d.usd.mint(admin, 100_000e18);
    }

    function _writeDeploymentJson() private {
        string memory key = "deployment";
        vm.serializeAddress(key, "RoleManager", address(d.roles));
        vm.serializeAddress(key, "MockUSD", address(d.usd));
        vm.serializeAddress(key, "Vault", address(d.vault));
        vm.serializeAddress(key, "PriceFeed", address(d.priceFeed));
        vm.serializeAddress(key, "NovaPerpToken", address(d.nova));
        vm.serializeAddress(key, "LeverageController", address(d.lev));
        vm.serializeAddress(key, "FeeDistributor", address(d.fees));
        vm.serializeAddress(key, "CollateralVault", address(d.cvault));
        vm.serializeAddress(key, "MarginManager", address(d.mm));
        vm.serializeAddress(key, "ChainlinkAdapter", address(d.clAdapter));
        vm.serializeAddress(key, "TWAPOracle", address(d.twap));
        vm.serializeAddress(key, "OracleAggregator", address(d.oracle));
        vm.serializeAddress(key, "BadDebtHandler", address(d.badDebt));
        vm.serializeAddress(key, "InsuranceFund", address(d.insurance));
        vm.serializeAddress(key, "LiquidationEngine", address(d.engine));
        vm.serializeAddress(key, "LiquidationBot", address(d.bot));
        vm.serializeAddress(key, "FundingRateEngine", address(d.funding));
        vm.serializeAddress(key, "RiskManager", address(d.risk));
        vm.serializeAddress(key, "PositionRouter", address(d.router));
        vm.serializeAddress(key, "OrderBook", address(d.orderBook));
        vm.serializeAddress(key, "StopLossManager", address(d.stopLoss));
        vm.serializeAddress(key, "LPVault", address(d.lpVault));
        vm.serializeAddress(key, "SettlementEngine", address(d.settlement));
        vm.serializeAddress(key, "RewardToken", address(d.rewardToken));
        vm.serializeAddress(key, "RewardDistributor", address(d.rewardDistributor));
        vm.serializeAddress(key, "EmergencyController", address(d.emergency));
        vm.serializeBytes32(key, "ETH_USD", ETH_USD);
        string memory finalJson = vm.serializeUint(key, "chainId", block.chainid);

        string memory outPath =
            string.concat("./frontend/lib/deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(finalJson, outPath);

        console2.log("Addresses written to", outPath);
    }

    function _logAddresses() private view {
        console2.log("// --- Phase 1 ---");
        console2.log("RoleManager        ", address(d.roles));
        console2.log("MockUSD (nUSD)     ", address(d.usd));
        console2.log("Vault              ", address(d.vault));
        console2.log("PriceFeed (legacy) ", address(d.priceFeed));
        console2.log("NovaPerpToken      ", address(d.nova));
        console2.log("// --- Phase 2a (oracle, wired BEFORE MarginManager) ---");
        console2.log("ChainlinkAdapter   ", address(d.clAdapter));
        console2.log("TWAPOracle         ", address(d.twap));
        console2.log("OracleAggregator   ", address(d.oracle));
        console2.log("// --- Phase 2 ---");
        console2.log("LeverageController ", address(d.lev));
        console2.log("FeeDistributor     ", address(d.fees));
        console2.log("CollateralVault    ", address(d.cvault));
        console2.log("MarginManager      ", address(d.mm));
        console2.log("// --- Phase 4 ---");
        console2.log("BadDebtHandler     ", address(d.badDebt));
        console2.log("InsuranceFund      ", address(d.insurance));
        console2.log("LiquidationEngine  ", address(d.engine));
        console2.log("LiquidationBot     ", address(d.bot));
        console2.log("// --- Phase 5 ---");
        console2.log("FundingRateEngine  ", address(d.funding));
        console2.log("RiskManager        ", address(d.risk));
        console2.log("PositionRouter     ", address(d.router));
        console2.log("OrderBook          ", address(d.orderBook));
        console2.log("StopLossManager    ", address(d.stopLoss));
        console2.log("// --- Phase 6 ---");
        console2.log("LPVault            ", address(d.lpVault));
        console2.log("SettlementEngine   ", address(d.settlement));
        console2.log("RewardToken (nRWD) ", address(d.rewardToken));
        console2.log("RewardDistributor  ", address(d.rewardDistributor));
        console2.log("EmergencyController", address(d.emergency));
        console2.log("// --- Market ---");
        console2.log("ETH_USD market id  ", uint256(ETH_USD));
    }
}
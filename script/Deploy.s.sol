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

/// @title DeployFull
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice Deploys and wires the complete Phase 1-6 protocol stack. Mirrors the
///         wiring sequence proven by Phase2Base -> Phase6Base (493/493 tests).
///
/// @dev STACK-TOO-DEEP NOTE: an earlier version of this script kept every deployed
///      contract as a local variable inside one `run()` function. With ~28 locals
///      alive at once (one per contract across 6 phases), solc's legacy codegen hit
///      "stack too deep" exactly like CollateralVault.liquidate and
///      MarginManager.liquidate did in Phase 4/6 — same root cause, different
///      contract. The fix is the same one applied there: it is NOT to enable
///      `via_ir` (that silently miscompiled TWAPOracle's cumulative-price math, see
///      foundry.toml's permanent `via_ir = false`), but to get locals out of any
///      single function's stack frame. Here, that means: all deployed addresses
///      live in the `Deployed` STORAGE struct below (state variables don't count
///      against the 16-slot local-variable stack limit), and `run()` is split into
///      one private function per phase, each touching only that phase's few new
///      locals before writing them into storage and returning.
///
/// @dev Run with (from the NovaPerpDEX/ root):
///
///      Local Anvil (instant blocks, free, recommended for iterating on the
///      frontend during 7.2-7.5):
///        anvil
///        forge script script/Deploy.s.sol:DeployFull \
///            --rpc-url http://127.0.0.1:8545 \
///            --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
///            --broadcast
///
///      Sepolia (real testnet, ~12s blocks, needs Sepolia ETH for gas):
///        forge script script/Deploy.s.sol:DeployFull \
///            --rpc-url https://sepolia.drpc.org \
///            --private-key $YOUR_SEPOLIA_PRIVATE_KEY \
///            --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
///
///      Anvil's account #0 key above is well-known and PUBLIC — local-dev only,
///      never fund it or use it anywhere except a local Anvil instance.
///      Writes addresses to frontend/lib/deployments/{chainId}.json (31337 for
///      Anvil, 11155111 for Sepolia) so both can coexist.
contract DeployFull is Script {
    bytes32 internal constant ETH_USD = keccak256("ETH-USD");

    uint256 internal constant STALENESS = 1 hours;
    uint256 internal constant MIN_COLLATERAL = 10e18; // $10
    uint256 internal constant POSITION_FEE_BPS = 10; // 0.1%
    uint256 internal constant START_PRICE = 2_000e18; // $2000
    uint256 internal constant KEEPER_REWARD_BPS = 2_000; // 20% of the liquidation fee
    uint256 internal constant INSURANCE_SEED = 100_000e18;
    uint256 internal constant LP_SEED = 1_000_000e18; // initial LPVault deposit
    uint256 internal constant FUNDING_MAX_RATE = 1e12; // small per-second cap
    uint256 internal constant DEFAULT_EPOCH_DURATION = 1 days;
    uint256 internal constant DEFAULT_LP_SHARE_BPS = 5_000; // 50%
    uint256 internal constant REWARD_FUND_AMOUNT = 100_000e18;
    uint256 internal constant REWARD_DURATION = 30 days;

    struct Deployed {
        RoleManager roles;
        MockERC20 usd;
        Vault vault;
        PriceFeed priceFeed;
        NovaPerpToken nova;
        LeverageController lev;
        FeeDistributor fees;
        CollateralVault cvault;
        MarginManager mm;
        ChainlinkAdapter clAdapter;
        TWAPOracle twap;
        OracleAggregator oracle;
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
        _deployPhase2();
        _deployPhase3();
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
    }

    function _deployPhase2() private {
        d.lev = new LeverageController(address(d.roles), MIN_COLLATERAL);
        d.fees = new FeeDistributor(
            address(d.roles), address(d.vault), address(d.usd), admin, POSITION_FEE_BPS
        );
        d.cvault = new CollateralVault(address(d.roles), address(d.vault));
        d.mm = new MarginManager(
            address(d.roles), address(d.priceFeed), address(d.lev), address(d.cvault), address(d.fees)
        );

        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.mm));
        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.cvault));
        d.roles.grantRole(d.roles.OPERATOR_ROLE(), address(d.fees));
        d.roles.grantRole(d.roles.PRICE_KEEPER_ROLE(), admin);

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

        d.priceFeed.setPrice(ETH_USD, START_PRICE);
    }

    function _deployPhase3() private {
        // Deployed for completeness/future wiring; the trade path uses the
        // simple `priceFeed` above (matching the proven test stack).
        d.clAdapter = new ChainlinkAdapter(address(d.roles));
        d.twap = new TWAPOracle(address(d.roles));
        d.oracle = new OracleAggregator(address(d.roles), address(d.clAdapter), address(d.twap));
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
        d.orderBook = new OrderBook(address(d.priceFeed), address(d.mm));
        d.stopLoss = new StopLossManager(address(d.priceFeed), address(d.mm));

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
        console2.log("PriceFeed          ", address(d.priceFeed));
        console2.log("NovaPerpToken      ", address(d.nova));
        console2.log("// --- Phase 2 ---");
        console2.log("LeverageController ", address(d.lev));
        console2.log("FeeDistributor     ", address(d.fees));
        console2.log("CollateralVault    ", address(d.cvault));
        console2.log("MarginManager      ", address(d.mm));
        console2.log("// --- Phase 3 ---");
        console2.log("ChainlinkAdapter   ", address(d.clAdapter));
        console2.log("TWAPOracle         ", address(d.twap));
        console2.log("OracleAggregator   ", address(d.oracle));
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
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
///         wiring sequence proven by Phase2Base -> Phase6Base (493/493 tests),
///         adapted for production shape:
///         - `liquidityPool` is the {LPVault} itself (not a bare EOA), seeded by a
///           real `lpVault.deposit()` so its share price is meaningful from block 1.
///         - {FundingRateEngine}'s open-interest source is {MarginManager} (real OI),
///           not the test's MockOpenInterest.
///         - A small nonzero funding max-rate and reward emission are configured so
///           the dashboard has live, nonzero values to display immediately.
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
///            --rpc-url $RPC_URL \
///            --private-key $PRIVATE_KEY \
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

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);
        address keeper = admin; // local dev: deployer also pushes prices
        address treasury = admin; // local dev: deployer also receives fees

        vm.startBroadcast(pk);

        RoleManager roles = new RoleManager(admin);
        MockERC20 usd = new MockERC20("Nova USD", "nUSD", 18);
        Vault vault = new Vault(address(usd), address(roles));
        PriceFeed priceFeed = new PriceFeed(address(roles), STALENESS);
        NovaPerpToken nova = new NovaPerpToken(address(roles), admin, 10_000_000e18);

        LeverageController lev = new LeverageController(address(roles), MIN_COLLATERAL);
        FeeDistributor fees =
            new FeeDistributor(address(roles), address(vault), address(usd), treasury, POSITION_FEE_BPS);
        CollateralVault cvault = new CollateralVault(address(roles), address(vault));
        MarginManager mm = new MarginManager(
            address(roles), address(priceFeed), address(lev), address(cvault), address(fees)
        );

        roles.grantRole(roles.OPERATOR_ROLE(), address(mm));
        roles.grantRole(roles.OPERATOR_ROLE(), address(cvault));
        roles.grantRole(roles.OPERATOR_ROLE(), address(fees));
        roles.grantRole(roles.PRICE_KEEPER_ROLE(), keeper);

        cvault.setFeeDistributor(address(fees));

        lev.addMarket(
            ETH_USD,
            DataTypes.MarketConfig({
                maxLeverage: 50e18,
                maintenanceMarginBps: 200,
                liquidationFeeBps: 100,
                maxOpenInterest: 10_000_000e18,
                isActive: true
            })
        );

        priceFeed.setPrice(ETH_USD, START_PRICE);

        // Oracle aggregator is deployed for completeness/future wiring but the trade
        // path uses the simple `priceFeed` above (matching the proven test stack).
        ChainlinkAdapter clAdapter = new ChainlinkAdapter(address(roles));
        TWAPOracle twap = new TWAPOracle(address(roles));
        OracleAggregator oracle = new OracleAggregator(address(roles), address(clAdapter), address(twap));

        BadDebtHandler badDebt = new BadDebtHandler(address(roles));
        InsuranceFund insurance = new InsuranceFund(address(roles), address(vault), address(usd));
        LiquidationEngine engine = new LiquidationEngine(address(roles), address(mm));
        LiquidationBot bot = new LiquidationBot(address(mm), address(engine), admin);

        roles.grantRole(roles.OPERATOR_ROLE(), address(insurance));
        roles.grantRole(roles.OPERATOR_ROLE(), address(badDebt));
        roles.grantRole(roles.LIQUIDATOR_ROLE(), address(engine));

        cvault.setInsuranceFund(address(insurance));
        cvault.setBadDebtHandler(address(badDebt));
        cvault.setKeeperRewardBps(KEEPER_REWARD_BPS);

        usd.mint(admin, INSURANCE_SEED);
        usd.approve(address(insurance), INSURANCE_SEED);
        insurance.seed(INSURANCE_SEED);

        FundingRateEngine funding = new FundingRateEngine(address(roles));
        funding.setOpenInterestSource(address(mm)); // real OI from MarginManager
        funding.initializeMarket(ETH_USD, FUNDING_MAX_RATE);

        RiskManager risk = new RiskManager(address(roles));
        risk.setRiskConfig(
            ETH_USD,
            RiskManager.RiskConfig({
                maxSkewBps: 0,
                baseFeeBps: 10,
                dynamicFactorBps: 0,
                configured: false
            })
        );

        mm.setFundingEngine(address(funding));
        mm.setRiskManager(address(risk));

        PositionRouter router = new PositionRouter(address(roles), address(mm));
        router.setFundingEngine(address(funding));
        OrderBook orderBook = new OrderBook(address(priceFeed), address(mm));
        StopLossManager stopLoss = new StopLossManager(address(priceFeed), address(mm));

        mm.setRouter(address(router), true);
        mm.setRouter(address(orderBook), true);
        mm.setRouter(address(stopLoss), true);

        LPVault lpVault = new LPVault(address(usd), address(vault));

        // liquidityPool is the LPVault itself: every settle()/liquidate() that moves
        // collateral into/out of `liquidityPool` is automatically reflected in
        // lpVault.totalAssets() and therefore in LP share price.
        cvault.setLiquidityPool(address(lpVault));

        SettlementEngine settlement = new SettlementEngine(
            address(roles), address(fees), address(lpVault), DEFAULT_EPOCH_DURATION, DEFAULT_LP_SHARE_BPS
        );
        roles.grantRole(roles.GOVERNOR_ROLE(), address(settlement));

        MockERC20 rewardToken = new MockERC20("Nova Reward", "nRWD", 18);
        RewardDistributor rewardDistributor =
            new RewardDistributor(address(roles), address(lpVault), address(rewardToken));

        EmergencyController emergency = new EmergencyController(address(roles));
        mm.setEmergencyController(address(emergency));

        // Seed the LP vault (== liquidityPool) so it can pay trader profits.
        usd.mint(admin, LP_SEED);
        usd.approve(address(lpVault), LP_SEED);
        lpVault.deposit(LP_SEED);

        // Fund a small reward emission so the staking tab has live numbers.
        rewardToken.mint(admin, REWARD_FUND_AMOUNT);
        rewardToken.approve(address(rewardDistributor), REWARD_FUND_AMOUNT);
        rewardDistributor.fund(REWARD_FUND_AMOUNT, REWARD_DURATION);

        // Anchor the funding index at deploy time.
        funding.updateFunding(ETH_USD);

        // Mint the deployer some nUSD for immediate frontend testing.
        usd.mint(admin, 100_000e18);

        vm.stopBroadcast();

        string memory key = "deployment";
        vm.serializeAddress(key, "RoleManager", address(roles));
        vm.serializeAddress(key, "MockUSD", address(usd));
        vm.serializeAddress(key, "Vault", address(vault));
        vm.serializeAddress(key, "PriceFeed", address(priceFeed));
        vm.serializeAddress(key, "NovaPerpToken", address(nova));
        vm.serializeAddress(key, "LeverageController", address(lev));
        vm.serializeAddress(key, "FeeDistributor", address(fees));
        vm.serializeAddress(key, "CollateralVault", address(cvault));
        vm.serializeAddress(key, "MarginManager", address(mm));
        vm.serializeAddress(key, "ChainlinkAdapter", address(clAdapter));
        vm.serializeAddress(key, "TWAPOracle", address(twap));
        vm.serializeAddress(key, "OracleAggregator", address(oracle));
        vm.serializeAddress(key, "BadDebtHandler", address(badDebt));
        vm.serializeAddress(key, "InsuranceFund", address(insurance));
        vm.serializeAddress(key, "LiquidationEngine", address(engine));
        vm.serializeAddress(key, "LiquidationBot", address(bot));
        vm.serializeAddress(key, "FundingRateEngine", address(funding));
        vm.serializeAddress(key, "RiskManager", address(risk));
        vm.serializeAddress(key, "PositionRouter", address(router));
        vm.serializeAddress(key, "OrderBook", address(orderBook));
        vm.serializeAddress(key, "StopLossManager", address(stopLoss));
        vm.serializeAddress(key, "LPVault", address(lpVault));
        vm.serializeAddress(key, "SettlementEngine", address(settlement));
        vm.serializeAddress(key, "RewardToken", address(rewardToken));
        vm.serializeAddress(key, "RewardDistributor", address(rewardDistributor));
        vm.serializeAddress(key, "EmergencyController", address(emergency));
        vm.serializeBytes32(key, "ETH_USD", ETH_USD);
        string memory finalJson = vm.serializeUint(key, "chainId", block.chainid);

        string memory outPath =
            string.concat("./frontend/lib/deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(finalJson, outPath);

        console2.log("// --- Phase 1 ---");
        console2.log("RoleManager        ", address(roles));
        console2.log("MockUSD (nUSD)     ", address(usd));
        console2.log("Vault              ", address(vault));
        console2.log("PriceFeed          ", address(priceFeed));
        console2.log("NovaPerpToken      ", address(nova));
        console2.log("// --- Phase 2 ---");
        console2.log("LeverageController ", address(lev));
        console2.log("FeeDistributor     ", address(fees));
        console2.log("CollateralVault    ", address(cvault));
        console2.log("MarginManager      ", address(mm));
        console2.log("// --- Phase 3 ---");
        console2.log("ChainlinkAdapter   ", address(clAdapter));
        console2.log("TWAPOracle         ", address(twap));
        console2.log("OracleAggregator   ", address(oracle));
        console2.log("// --- Phase 4 ---");
        console2.log("BadDebtHandler     ", address(badDebt));
        console2.log("InsuranceFund      ", address(insurance));
        console2.log("LiquidationEngine  ", address(engine));
        console2.log("LiquidationBot     ", address(bot));
        console2.log("// --- Phase 5 ---");
        console2.log("FundingRateEngine  ", address(funding));
        console2.log("RiskManager        ", address(risk));
        console2.log("PositionRouter     ", address(router));
        console2.log("OrderBook          ", address(orderBook));
        console2.log("StopLossManager    ", address(stopLoss));
        console2.log("// --- Phase 6 ---");
        console2.log("LPVault            ", address(lpVault));
        console2.log("SettlementEngine   ", address(settlement));
        console2.log("RewardToken (nRWD) ", address(rewardToken));
        console2.log("RewardDistributor  ", address(rewardDistributor));
        console2.log("EmergencyController", address(emergency));
        console2.log("// --- Market ---");
        console2.log("ETH_USD market id  ", uint256(ETH_USD));
        console2.log("// --- Output ---");
        console2.log("Addresses written to", outPath);
    }
}
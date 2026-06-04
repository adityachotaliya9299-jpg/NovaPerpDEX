// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RoleManager} from "../src/core/RoleManager.sol";
import {Vault} from "../src/core/Vault.sol";
import {PriceFeed} from "../src/core/PriceFeed.sol";
import {LeverageController} from "../src/core/LeverageController.sol";
import {FeeDistributor} from "../src/core/FeeDistributor.sol";
import {CollateralVault} from "../src/core/CollateralVault.sol";
import {MarginManager} from "../src/core/MarginManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";

/// @title Phase2Base
/// @author Aditya Chotaliya [adityachotaliya.vercel.app]
/// @notice Deploys the full margin-engine stack on an 18-decimal USD collateral token
///         and wires roles, market config and a funded counterparty pool.
/// @dev The protocol collateral is an 18-dec USD stable so that vault units map 1:1 to
///      USD WAD, keeping size / collateral / PnL math free of decimal conversions.
contract Phase2Base is Test {
    RoleManager internal roles;
    Vault internal vault;
    PriceFeed internal priceFeed;
    LeverageController internal lev;
    FeeDistributor internal fees;
    CollateralVault internal cvault;
    MarginManager internal mm;
    MockERC20 internal usd;

    address internal admin = makeAddr("admin");
    address internal keeper = makeAddr("keeper");
    address internal treasury = makeAddr("treasury");
    address internal pool = makeAddr("pool");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant ETH_USD = keccak256("ETH-USD");

    uint256 internal constant STALENESS = 1 hours;
    uint256 internal constant MIN_COLLATERAL = 10e18; // $10
    uint256 internal constant POSITION_FEE_BPS = 10; // 0.1%
    uint256 internal constant START_PRICE = 2_000e18; // $2000

    function setUp() public virtual {
        vm.startPrank(admin);
        roles = new RoleManager(admin);
        usd = new MockERC20("Nova USD", "nUSD", 18);
        vault = new Vault(address(usd), address(roles));
        priceFeed = new PriceFeed(address(roles), STALENESS);
        lev = new LeverageController(address(roles), MIN_COLLATERAL);
        fees = new FeeDistributor(
            address(roles), address(vault), address(usd), treasury, POSITION_FEE_BPS
        );
        cvault = new CollateralVault(address(roles), address(vault));
        mm = new MarginManager(
            address(roles), address(priceFeed), address(lev), address(cvault), address(fees)
        );

        // Roles: both money-movers are operators; keeper pushes prices.
        roles.grantRole(roles.OPERATOR_ROLE(), address(mm));
        roles.grantRole(roles.OPERATOR_ROLE(), address(cvault));
        roles.grantRole(roles.OPERATOR_ROLE(), address(fees));
        roles.grantRole(roles.PRICE_KEEPER_ROLE(), keeper);

        // Wire the collateral vault to its pool and fee sink.
        cvault.setLiquidityPool(pool);
        cvault.setFeeDistributor(address(fees));

        // Register the ETH-USD market: 50x max, 2% maintenance, 1% liq fee, $10M OI cap.
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
        vm.stopPrank();

        // Seed the price.
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, START_PRICE);

        // Fund the counterparty pool with locked collateral so it can pay profits.
        _fundPool(2_000_000e18);
    }

    /// @notice Mints `amount` USD to `who` and approves + deposits into the vault.
    function _deposit(address who, uint256 amount) internal {
        usd.mint(who, amount);
        vm.startPrank(who);
        usd.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    /// @notice Funds the pool's locked balance (operator locks on its behalf).
    function _fundPool(uint256 amount) internal {
        usd.mint(pool, amount);
        vm.startPrank(pool);
        usd.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
        // The CollateralVault holds OPERATOR_ROLE; impersonate it to lock pool funds.
        vm.prank(address(cvault));
        vault.lock(pool, amount);
    }

    /// @notice Refresh the oracle price (also resets staleness).
    function _setPrice(uint256 price) internal {
        vm.prank(keeper);
        priceFeed.setPrice(ETH_USD, price);
    }
}

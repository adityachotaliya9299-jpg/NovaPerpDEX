// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../src/core/Vault.sol";
import {PriceFeed} from "../../src/core/PriceFeed.sol";
import {MarginManager} from "../../src/core/MarginManager.sol";
import {LiquidationEngine} from "../../src/core/LiquidationEngine.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {Phase4Base} from "../Phase4Base.sol";

/// @notice Randomized open / close / price-move / liquidate flows across two traders.
contract LiquidationHandler is Test {
    MarginManager internal mm;
    LiquidationEngine internal engine;
    Vault internal vault;
    PriceFeed internal feed;
    MockERC20 internal usd;
    address internal keeper;
    address internal liquidator;
    bytes32 internal market;
    address[] internal traders;

    constructor(
        MarginManager _mm,
        LiquidationEngine _engine,
        Vault _vault,
        PriceFeed _feed,
        MockERC20 _usd,
        address _keeper,
        address _liquidator,
        bytes32 _market,
        address t1,
        address t2
    ) {
        mm = _mm;
        engine = _engine;
        vault = _vault;
        feed = _feed;
        usd = _usd;
        keeper = _keeper;
        liquidator = _liquidator;
        market = _market;
        traders.push(t1);
        traders.push(t2);
    }

    function _t(uint256 s) internal view returns (address) {
        return traders[s % traders.length];
    }

    function open(uint256 seed, uint256 size, uint256 collateral, bool isLong) external {
        address t = _t(seed);
        DataTypes.Side side = isLong ? DataTypes.Side.LONG : DataTypes.Side.SHORT;
        if (mm.getPosition(t, market, side).size != 0) return;
        collateral = bound(collateral, 20e18, 5_000e18);
        size = bound(size, collateral, collateral * 30);

        usd.mint(t, collateral + 200e18);
        vm.startPrank(t);
        usd.approve(address(vault), type(uint256).max);
        vault.deposit(collateral + 200e18);
        vm.stopPrank();

        vm.prank(t);
        try mm.increasePosition(market, side, size, collateral) {} catch {}
    }

    function close(uint256 seed, bool isLong) external {
        address t = _t(seed);
        DataTypes.Side side = isLong ? DataTypes.Side.LONG : DataTypes.Side.SHORT;
        if (mm.getPosition(t, market, side).size == 0) return;
        vm.prank(t);
        try mm.closePosition(market, side) {} catch {}
    }

    function liquidate(uint256 seed, bool isLong) external {
        address t = _t(seed);
        DataTypes.Side side = isLong ? DataTypes.Side.LONG : DataTypes.Side.SHORT;
        if (!mm.isLiquidatable(t, market, side)) return;
        try engine.liquidateFor(t, market, side, liquidator) {} catch {}
    }

    function movePrice(uint256 price) external {
        price = bound(price, 1_000e18, 4_000e18);
        vm.prank(keeper);
        feed.setPrice(market, price);
    }
}

/// @title LiquidationInvariantTest
/// @notice Even through liquidations, insurance cover and socialized bad debt, the
///         vault stays token-solvent and no collateral leaks from the accounted set.
///         (Bad debt is unbacked accounting — it moves no tokens — so conservation holds.)
contract LiquidationInvariantTest is Phase4Base {
    LiquidationHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new LiquidationHandler(
            mm, engine, vault, priceFeed, usd, keeper, liquidator, ETH_USD, alice, bob
        );
        targetContract(address(handler));
    }

    function invariant_VaultSolvent() public view {
        assertEq(usd.balanceOf(address(vault)), vault.totalCollateral());
    }

    function invariant_NoCollateralLeak() public view {
        uint256 sum = vault.totalOf(alice) + vault.totalOf(bob) + vault.totalOf(pool)
            + vault.totalOf(address(fees)) + vault.totalOf(address(insurance))
            + vault.totalOf(liquidator);
        assertEq(sum, vault.totalCollateral());
    }
}
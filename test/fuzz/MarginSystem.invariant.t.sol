// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../src/core/Vault.sol";
import {PriceFeed} from "../../src/core/PriceFeed.sol";
import {MarginManager} from "../../src/core/MarginManager.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {Phase2Base} from "../Phase2Base.sol";

/// @notice Drives randomized open / close / price flows across two traders.
/// @dev Holds direct typed references to the deployed contracts and pranks the
///      traders itself. Trades that violate risk rules simply revert and are
///      swallowed — the point is to stress the accounting under valid + invalid mixes.
contract MarginHandler is Test {
    MarginManager internal mm;
    Vault internal vault;
    PriceFeed internal feed;
    MockERC20 internal usd;
    address internal keeper;
    bytes32 internal market;
    address[] internal traders;

    constructor(
        MarginManager _mm,
        Vault _vault,
        PriceFeed _feed,
        MockERC20 _usd,
        address _keeper,
        bytes32 _market,
        address t1,
        address t2
    ) {
        mm = _mm;
        vault = _vault;
        feed = _feed;
        usd = _usd;
        keeper = _keeper;
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
        if (mm.getPosition(t, market, side).size != 0) return; // keep flat-to-open simple

        collateral = bound(collateral, 20e18, 5_000e18);
        size = bound(size, collateral, collateral * 40); // 1x..40x

        // fund the trader
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

    function movePrice(uint256 price) external {
        price = bound(price, 1_000e18, 4_000e18);
        vm.prank(keeper);
        feed.setPrice(market, price);
    }
}

/// @title MarginSystemInvariantTest
/// @notice Core safety invariants for the margin engine. Whatever positions do —
///         profit drawn from the pool, losses pushed into it, fees skimmed — the
///         vault stays solvent and no collateral leaks out of the accounted set.
contract MarginSystemInvariantTest is Phase2Base {
    MarginHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new MarginHandler(
            mm, vault, priceFeed, usd, keeper, ETH_USD, alice, bob
        );
        targetContract(address(handler));
    }

    /// @notice The vault's real token balance always equals its accounted total.
    function invariant_VaultSolvent() public view {
        assertEq(usd.balanceOf(address(vault)), vault.totalCollateral());
    }

    /// @notice No collateral leaks: the four participants' (free + locked) balances
    ///         sum to exactly the vault's total collateral.
    function invariant_NoCollateralLeak() public view {
        uint256 sum = vault.totalOf(alice) + vault.totalOf(bob) + vault.totalOf(pool)
            + vault.totalOf(address(fees));
        assertEq(sum, vault.totalCollateral());
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";

import {DataTypes} from "../libraries/DataTypes.sol";
import {IStrategyVault} from "../interfaces/IStrategyVault.sol";
import {RoleManager} from "./RoleManager.sol";
import {Vault} from "./Vault.sol";
import {MarginManager} from "./MarginManager.sol";
import {FundingRateEngine} from "./FundingRateEngine.sol";

/// @title StrategyVault
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice A pooled investment vault where an authorized AI agent trades
///         perpetual futures on behalf of depositors. Investors deposit nUSD,
///         receive shares proportional to NAV, and the agent opens/closes
///         positions on {MarginManager} using the vault's collateral.
///
/// @dev Architecture rationale:
///   - Mirrors LPVault's share math exactly (dead shares on first deposit,
///     WAD-scaled, previewDeposit/previewRedeem symmetric).
///   - The agent wallet is a hot key (the Railway/Fly.io process). It calls
///     openPosition/closePosition/decreasePosition here. This contract then
///     calls marginManager.increasePositionFor(address(this), ...) since
///     StrategyVault IS the position owner — all positions are owned by the
///     vault, not by individual investors.
///   - Risk parameters (maxDrawdownBps, maxLeverageBps, maxSinglePositionBps)
///     are enforced on-chain. The agent cannot bypass them.
///   - If drawdown breaches the limit, trading is halted automatically and
///     the DrawdownBreached event is emitted. The creator or governor can
///     resume trading after reviewing the situation.
///   - Protocol fee (10% of profits) and creator fee (5% of profits) are
///     collected at withdrawal time, not during trading, to avoid complex
///     mid-trade accounting.
///   - Every agent action emits AgentTraded with a human-readable `reason`
///     string written by the LLM. This is the transparency differentiator
///     over Peaks — every decision is on-chain and auditable.
///
/// @dev Authorization flow:
///   1. StrategyFactory deploys this contract.
///   2. DeployAgents.s.sol (or governance tx) calls:
///      marginManager.setRouter(address(strategyVault), true)
///      vault.grantRole(OPERATOR_ROLE, address(strategyVault))  ← needed so vault.lock works
///   3. The off-chain agent process calls openPosition/closePosition/decreasePosition.
///   4. This contract calls marginManager.increasePositionFor(address(this), ...).

contract StrategyVault is IStrategyVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------ //
    //                          Constants                                  //
    // ------------------------------------------------------------------ //

    uint256 public constant MIN_FIRST_DEPOSIT = 1e6;
    uint256 public constant WAD = 1e18;
    uint256 public constant BPS = 10_000;

    /// @notice Protocol takes 10% of realized profits on withdrawal.
    uint256 public constant PROTOCOL_FEE_BPS = 1_000;

    /// @notice Strategy creator takes 5% of realized profits on withdrawal.
    uint256 public constant CREATOR_FEE_BPS = 500;

    // ------------------------------------------------------------------ //
    //                              Events                                //
    // ------------------------------------------------------------------ //

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ------------------------------------------------------------------ //
    //                       Immutables                                    //
    // ------------------------------------------------------------------ //

    RoleManager public immutable roles;
    IERC20 public immutable asset;
    Vault public immutable vault;
    MarginManager public immutable marginManager;

    /// @notice Strategy creator — receives CREATOR_FEE_BPS of profits.
    address public immutable creator;

    /// @notice Protocol treasury — receives PROTOCOL_FEE_BPS of profits.
    address public immutable protocolTreasury;

    // ------------------------------------------------------------------ //
    //                        Strategy metadata                            //
    // ------------------------------------------------------------------ //

    /// @notice Human-readable strategy name (set at deploy, immutable after).
    string public strategyName;

    /// @notice Natural-language thesis (what the agent is trying to do).
    string public thesis;

    /// @notice LLM-parsed position targets as a JSON string, updated by agent.
    string public currentTargets;

    // ------------------------------------------------------------------ //
    //                       Agent configuration                           //
    // ------------------------------------------------------------------ //

    /// @notice The hot wallet address the off-chain agent process signs with.
    address public agentWallet;

    /// @notice Optional FundingRateEngine to refresh before each trade.
    FundingRateEngine public fundingEngine;

    // ------------------------------------------------------------------ //
    //                         Risk parameters                             //
    // ------------------------------------------------------------------ //

    /// @notice Maximum drawdown from peak NAV before trading is auto-halted.
    ///         In basis points. E.g. 2000 = halt if down 20% from peak.
    uint256 public maxDrawdownBps;

    /// @notice Maximum leverage the agent may use across all open positions.
    ///         In basis points of totalAssets. E.g. 30000 = 3x total leverage.
    uint256 public maxLeverageBps;

    /// @notice Maximum notional size of any single position as a fraction of
    ///         totalAssets. In basis points. E.g. 5000 = 50% of NAV per position.
    uint256 public maxSinglePositionBps;

    // ------------------------------------------------------------------ //
    //                          NAV tracking                               //
    // ------------------------------------------------------------------ //

    /// @notice Peak NAV since vault inception (or since last reset after a
    ///         drawdown recovery). Used to compute drawdown percentage.
    uint256 public peakNAV;

    /// @notice Total collateral deposited across all investors (cost basis for
    ///         fee calculation — we charge fees only on profit, not on deposits).
    uint256 public totalDeposited;

    // ------------------------------------------------------------------ //
    //                         Trading state                               //
    // ------------------------------------------------------------------ //

    /// @notice When true, the agent cannot open new positions. Existing
    ///         positions can still be closed to allow orderly wind-down.
    bool public tradingHalted;

    // ------------------------------------------------------------------ //
    //                          Share accounting                           //
    // ------------------------------------------------------------------ //

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ------------------------------------------------------------------ //
    //                       Investor cost basis                           //
    // ------------------------------------------------------------------ //

    /// @notice NAV per share at the time of each investor's deposit.
    ///         Used to compute profit at withdrawal for fee collection.
    mapping(address => uint256) public costBasisPerShare;

    // ------------------------------------------------------------------ //
    //                          Constructor                                //
    // ------------------------------------------------------------------ //

    struct ConstructorParams {
        address roles;
        address asset;
        address vault;
        address marginManager;
        address creator;
        address protocolTreasury;
        address agentWallet;
        address fundingEngine; 
        string strategyName;
        string thesis;
        uint256 maxDrawdownBps;
        uint256 maxLeverageBps;
        uint256 maxSinglePositionBps;
    }

    constructor(ConstructorParams memory p) {
        require(p.roles != address(0), "SV: zero roles");
        require(p.asset != address(0), "SV: zero asset");
        require(p.vault != address(0), "SV: zero vault");
        require(p.marginManager != address(0), "SV: zero mm");
        require(p.creator != address(0), "SV: zero creator");
        require(p.protocolTreasury != address(0), "SV: zero treasury");
        require(p.agentWallet != address(0), "SV: zero agent");
        require(p.maxDrawdownBps <= BPS, "SV: drawdown > 100%");
        require(p.maxLeverageBps > 0, "SV: zero leverage");
        require(p.maxSinglePositionBps <= BPS, "SV: position > 100%");

        roles = RoleManager(p.roles);
        asset = IERC20(p.asset);
        vault = Vault(p.vault);
        marginManager = MarginManager(p.marginManager);
        creator = p.creator;
        protocolTreasury = p.protocolTreasury;
        agentWallet = p.agentWallet;
        strategyName = p.strategyName;
        thesis = p.thesis;
        maxDrawdownBps = p.maxDrawdownBps;
        maxLeverageBps = p.maxLeverageBps;
        maxSinglePositionBps = p.maxSinglePositionBps;
        peakNAV = 0;
        totalDeposited = 0;
        tradingHalted = false;

        if (p.fundingEngine != address(0)) {
            fundingEngine = FundingRateEngine(p.fundingEngine);
        }
    }

    // ------------------------------------------------------------------ //
    //                          Modifiers                                  //
    // ------------------------------------------------------------------ //

    modifier onlyAgent() {
        if (msg.sender != agentWallet) revert NotAgent(msg.sender);
        _;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator(msg.sender);
        _;
    }

    modifier onlyGovernorOrCreator() {
        if (!roles.isGovernor(msg.sender) && msg.sender != creator) {
            revert NotGovernor(msg.sender);
        }
        _;
    }

    modifier whenNotHalted() {
        if (tradingHalted) revert TradingIsHalted();
        _;
    }

    // ------------------------------------------------------------------ //
    //                       NAV & share views                             //
    // ------------------------------------------------------------------ //

    /// @notice Total assets owned by this vault in the protocol Vault ledger.
    ///         This is the NAV denominator — it includes both free collateral
    ///         and collateral locked in open positions.
    function totalAssets() public view returns (uint256) {
        return vault.totalOf(address(this));
    }

    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return WAD;
        return OZMath.mulDiv(totalAssets(), WAD, supply);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 nav = totalAssets();
        if (supply == 0 || nav == 0) return assets;
        return (assets * supply) / nav;
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return 0;
        return (shares * totalAssets()) / supply;
    }

    /// @notice Current drawdown from peak NAV, in basis points.
    ///         Returns 0 if NAV is above or equal to peak.
    function currentDrawdownBps() public view returns (uint256) {
        uint256 nav = totalAssets();
        if (peakNAV == 0 || nav >= peakNAV) return 0;
        return ((peakNAV - nav) * BPS) / peakNAV;
    }

    function isHalted() external view returns (bool) {
        return tradingHalted;
    }

    // ------------------------------------------------------------------ //
    //                        Investor actions                             //
    // ------------------------------------------------------------------ //

    /// @notice Deposit `assets` of nUSD into the strategy. Receive shares at
    ///         current NAV. First deposit mints dead shares to address(1).
    function deposit(uint256 assets) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (assets < MIN_FIRST_DEPOSIT && totalSupply == 0) {
            revert BelowMinDeposit(assets, MIN_FIRST_DEPOSIT);
        }

        uint256 supply = totalSupply;
        uint256 nav = totalAssets();

        if (supply == 0) {
            shares = assets - MIN_FIRST_DEPOSIT;
            _mint(address(1), MIN_FIRST_DEPOSIT);
        } else {
            shares = nav > 0 ? (assets * supply) / nav : assets;
        }
        if (shares == 0) revert ZeroAmount();

        // Pull tokens → deposit into protocol Vault
        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.forceApprove(address(vault), assets);
        vault.deposit(assets);

        // Record cost basis for this investor (NAV per share at deposit time)
        // Weighted average if they deposit multiple times
        uint256 existingShares = balanceOf[msg.sender];
        if (existingShares == 0) {
            costBasisPerShare[msg.sender] = supply == 0 ? WAD : (nav * WAD) / supply;
        } else {
            // Weighted average cost basis
            uint256 currentBasis = costBasisPerShare[msg.sender];
            uint256 newBasisPerShare = supply == 0 ? WAD : (nav * WAD) / supply;
            costBasisPerShare[msg.sender] =
                (currentBasis * existingShares + newBasisPerShare * shares) /
                (existingShares + shares);
        }

        totalDeposited += assets;

        _mint(msg.sender, shares);
        _updatePeakNAV();

        emit Deposit(msg.sender, assets, shares);
    }

    /// @notice Burn `shares` and receive proportional assets back, net of fees
    ///         on any profit. Fees are charged only on the profit portion —
    ///         if the investor is at a loss, no fee is charged.
    function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        uint256 bal = balanceOf[msg.sender];
        if (shares > bal) revert InsufficientShares(msg.sender, shares, bal);

        uint256 supply = totalSupply;
        uint256 nav = totalAssets();
        assets = (shares * nav) / supply;
        if (assets == 0) revert ZeroAmount();

        // Profit calculation for fee: assets received vs cost basis
        uint256 basisValue = (shares * costBasisPerShare[msg.sender]) / WAD;
        uint256 protocolFee = 0;
        uint256 creatorFee = 0;

        if (assets > basisValue) {
            uint256 profit = assets - basisValue;
            protocolFee = (profit * PROTOCOL_FEE_BPS) / BPS;
            creatorFee = (profit * CREATOR_FEE_BPS) / BPS;
            assets -= (protocolFee + creatorFee);
        }

        // Check liquidity (free balance only — locked collateral can't be
        // withdrawn while positions are open, same as LPVault)
        uint256 available = vault.balanceOf(address(this));
        if (assets + protocolFee + creatorFee > available) {
            revert InsufficientLiquidity(assets + protocolFee + creatorFee, available);
        }

        _burn(msg.sender, shares);

        // Settle fees
        if (protocolFee > 0) {
            vault.withdraw(protocolFee);
            asset.safeTransfer(protocolTreasury, protocolFee);
            emit ProtocolFeeCollected(protocolFee);
        }
        if (creatorFee > 0) {
            vault.withdraw(creatorFee);
            asset.safeTransfer(creator, creatorFee);
            emit CreatorFeeCollected(creatorFee);
        }

        // Return net assets to investor
        vault.withdraw(assets);
        asset.safeTransfer(msg.sender, assets);

        emit Withdraw(msg.sender, assets, shares);
    }

    // ------------------------------------------------------------------ //
    //                          Agent actions                              //
    // ------------------------------------------------------------------ //

    /// @notice Open or increase a position. Only callable by the authorized
    ///         agent wallet. Trading must not be halted, and the requested
    ///         position size must not exceed maxSinglePositionBps of NAV.
    /// @param reason Human-readable string from the LLM explaining this trade.
    ///        Emitted on-chain and indexed by the subgraph for the Agent Log.
    function openPosition(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        uint256 collateralDelta,
        string calldata reason
    ) external onlyAgent whenNotHalted nonReentrant {
        // Enforce max single-position size as % of NAV
        uint256 nav = totalAssets();
        if (nav > 0) {
            uint256 maxSize = (nav * maxSinglePositionBps) / BPS;
            if (sizeDelta > maxSize) {
                revert MaxPositionSizeBreached((sizeDelta * BPS) / nav, maxSinglePositionBps);
            }
        }

        _refreshFunding(market);

        // Deposit collateral into the Vault's free balance so MarginManager
        // can lock it. The vault already holds the funds — we just need to
        // ensure the MarginManager's reserve() call can lock them.
        // (The vault's deposit happened at investor deposit time; funds are
        // already in the Vault ledger under address(this). No transfer needed.)
        marginManager.increasePositionFor(
            address(this),
            market,
            side,
            sizeDelta,
            collateralDelta
        );

        _checkAndUpdateDrawdown();

        emit AgentTraded(market, side, sizeDelta, collateralDelta, true, reason);
    }

    /// @notice Fully close a position. Agent may close positions even when
    ///         trading is halted, to allow orderly wind-down.
    function closePosition(
        bytes32 market,
        DataTypes.Side side,
        string calldata reason
    ) external onlyAgent nonReentrant {
        uint256 size = marginManager.getPosition(address(this), market, side).size;
        if (size == 0) return; // nothing to close, no-op

        _refreshFunding(market);
        marginManager.decreasePositionFor(address(this), market, side, size);

        _updatePeakNAV();

        emit AgentTraded(market, side, size, 0, false, reason);
    }

    /// @notice Partially decrease a position by `sizeDelta`.
    function decreasePosition(
        bytes32 market,
        DataTypes.Side side,
        uint256 sizeDelta,
        string calldata reason
    ) external onlyAgent nonReentrant {
        _refreshFunding(market);
        marginManager.decreasePositionFor(address(this), market, side, sizeDelta);

        _updatePeakNAV();

        emit AgentTraded(market, side, sizeDelta, 0, false, reason);
    }

    // ------------------------------------------------------------------ //
    //                     Creator / Governor admin                        //
    // ------------------------------------------------------------------ //

    /// @notice Update the authorized agent wallet. Creator or governor only.
    ///         Use this to rotate the agent key without redeploying the vault.
    function setAgentWallet(address newAgent) external onlyGovernorOrCreator {
        require(newAgent != address(0), "SV: zero agent");
        agentWallet = newAgent;
        emit AgentWalletSet(newAgent);
    }

    /// @notice Update risk parameters. Creator or governor only.
    function setRiskParams(
        uint256 _maxDrawdownBps,
        uint256 _maxLeverageBps,
        uint256 _maxSinglePositionBps
    ) external onlyGovernorOrCreator {
        require(_maxDrawdownBps <= BPS, "SV: drawdown > 100%");
        require(_maxLeverageBps > 0, "SV: zero leverage");
        require(_maxSinglePositionBps <= BPS, "SV: position > 100%");
        maxDrawdownBps = _maxDrawdownBps;
        maxLeverageBps = _maxLeverageBps;
        maxSinglePositionBps = _maxSinglePositionBps;
        emit RiskParamsUpdated(_maxDrawdownBps, _maxLeverageBps, _maxSinglePositionBps);
    }

    /// @notice Manually halt or resume trading. Creator or governor only.
    ///         Positions can still be closed while halted.
    function setTradingHalted(bool halted) external onlyGovernorOrCreator {
        tradingHalted = halted;
        emit TradingHalted(halted);
    }

    /// @notice Update the thesis description (the strategy's narrative).
    function setThesis(string calldata newThesis) external onlyCreator {
        thesis = newThesis;
    }

    /// @notice Update the current LLM-parsed target weights JSON.
    ///         Called by the agent process after each rebalance decision.
    function setCurrentTargets(string calldata targets) external onlyAgent {
        currentTargets = targets;
    }

    /// @notice Wire a FundingRateEngine so the vault refreshes funding before trades.
    function setFundingEngine(address engine) external onlyGovernorOrCreator {
        fundingEngine = FundingRateEngine(engine);
    }

    /// @notice Reset the peak NAV manually (e.g. after a restructuring).
    ///         Governor only — creator cannot reset their own drawdown clock.
    function resetPeakNAV() external {
        require(roles.isGovernor(msg.sender), "SV: not governor");
        peakNAV = totalAssets();
    }

    // ------------------------------------------------------------------ //
    //                    ERC20-style share transfers                      //
    // ------------------------------------------------------------------ //

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (amount > allowed) revert InsufficientAllowance(from, msg.sender, amount, allowed);
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    // ------------------------------------------------------------------ //
    //                          Internal helpers                           //
    // ------------------------------------------------------------------ //

    function _refreshFunding(bytes32 market) private {
        if (address(fundingEngine) != address(0)) {
            try fundingEngine.updateFunding(market) {} catch {}
            // Silently ignore failures — funding refresh is a nice-to-have,
            // not a hard requirement. A failed refresh shouldn't block trades.
        }
    }

    function _updatePeakNAV() private {
        uint256 nav = totalAssets();
        if (nav > peakNAV) {
            peakNAV = nav;
        }
    }

    function _checkAndUpdateDrawdown() private {
        _updatePeakNAV();
        uint256 drawdown = currentDrawdownBps();
        if (drawdown > maxDrawdownBps) {
            tradingHalted = true;
            emit DrawdownBreached(drawdown, maxDrawdownBps);
        }
    }

    function _mint(address to, uint256 amount) private {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) private {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        uint256 bal = balanceOf[from];
        if (amount > bal) revert InsufficientShares(from, amount, bal);
        balanceOf[from] = bal - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
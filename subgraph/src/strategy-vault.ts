import { BigInt } from "@graphprotocol/graph-ts";
import {
  Strategy,
  StrategyTrade,
  StrategyDeposit,
  StrategyWithdraw,
  DrawdownEvent,
  StrategyPosition,
} from "../generated/schema";
import {
  Deposit,
  Withdraw,
  AgentTraded,
  DrawdownBreached,
  TradingHalted,
} from "../generated/templates/StrategyVault/StrategyVault";

function strategyPositionId(strategyAddr: string, investorAddr: string): string {
  return strategyAddr + "-" + investorAddr;
}

export function handleStrategyDeposit(event: Deposit): void {
  // event.address is the specific vault instance that emitted this — since
  // this handler runs once per template instance, event.address tells us
  // WHICH StrategyVault this deposit happened on.
  const vaultAddr = event.address;
  const vaultId = vaultAddr.toHexString();

  const strategy = Strategy.load(vaultId);
  if (strategy == null) return; // shouldn't happen — created before template instantiation

  strategy.totalDeposited = strategy.totalDeposited.plus(event.params.assets);
  strategy.save();

  const dep = new StrategyDeposit(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  dep.strategy = vaultAddr;
  dep.investor = event.params.investor;
  dep.assets = event.params.assets;
  dep.shares = event.params.shares;
  dep.timestamp = event.block.timestamp;
  dep.txHash = event.transaction.hash;
  dep.save();

  const posId = strategyPositionId(vaultId, event.params.investor.toHexString());
  let pos = StrategyPosition.load(posId);
  const isNewInvestor = pos == null;
  if (pos == null) {
    pos = new StrategyPosition(posId);
    pos.strategy = vaultAddr;
    pos.investor = event.params.investor;
    pos.sharesHeld = BigInt.zero();
    pos.totalDeposited = BigInt.zero();
    pos.totalWithdrawn = BigInt.zero();
    pos.firstDepositAt = event.block.timestamp;
  }
  pos.sharesHeld = pos.sharesHeld.plus(event.params.shares);
  pos.totalDeposited = pos.totalDeposited.plus(event.params.assets);
  pos.lastActivityAt = event.block.timestamp;
  pos.save();

  if (isNewInvestor) {
    strategy.investorCount = strategy.investorCount + 1;
    strategy.save();
  }
}

export function handleStrategyWithdraw(event: Withdraw): void {
  const vaultAddr = event.address;
  const vaultId = vaultAddr.toHexString();

  const strategy = Strategy.load(vaultId);
  if (strategy == null) return;

  strategy.totalWithdrawn = strategy.totalWithdrawn.plus(event.params.assets);
  strategy.save();

  const wd = new StrategyWithdraw(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  wd.strategy = vaultAddr;
  wd.investor = event.params.investor;
  wd.assets = event.params.assets;
  wd.shares = event.params.shares;
  wd.timestamp = event.block.timestamp;
  wd.txHash = event.transaction.hash;
  wd.save();

  const posId = strategyPositionId(vaultId, event.params.investor.toHexString());
  const pos = StrategyPosition.load(posId);
  if (pos != null) {
    pos.sharesHeld = pos.sharesHeld.minus(event.params.shares);
    pos.totalWithdrawn = pos.totalWithdrawn.plus(event.params.assets);
    pos.lastActivityAt = event.block.timestamp;
    pos.save();
  }
}

export function handleAgentTraded(event: AgentTraded): void {
  const vaultAddr = event.address;
  const vaultId = vaultAddr.toHexString();

  const strategy = Strategy.load(vaultId);
  if (strategy != null) {
    strategy.tradeCount = strategy.tradeCount + 1;
    strategy.lastTradeAt = event.block.timestamp;
    strategy.save();
  }

  const trade = new StrategyTrade(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  trade.strategy = vaultAddr;
  trade.market = event.params.market;
  trade.side = event.params.side;
  trade.sizeDelta = event.params.sizeDelta;
  trade.collateralDelta = event.params.collateralDelta;
  trade.isIncrease = event.params.isIncrease;
  trade.reason = event.params.reason;
  trade.timestamp = event.block.timestamp;
  trade.txHash = event.transaction.hash;
  trade.save();
}

export function handleDrawdownBreached(event: DrawdownBreached): void {
  const vaultAddr = event.address;
  const vaultId = vaultAddr.toHexString();

  const strategy = Strategy.load(vaultId);
  if (strategy != null) {
    strategy.tradingHalted = true;
    strategy.currentDrawdownBpsAtLastUpdate = event.params.currentDrawdownBps;
    strategy.save();
  }

  const dd = new DrawdownEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  dd.strategy = vaultAddr;
  dd.currentDrawdownBps = event.params.currentDrawdownBps;
  dd.limitBps = event.params.limitBps;
  dd.timestamp = event.block.timestamp;
  dd.txHash = event.transaction.hash;
  dd.save();
}

export function handleTradingHalted(event: TradingHalted): void {
  const vaultId = event.address.toHexString();
  const strategy = Strategy.load(vaultId);
  if (strategy != null) {
    strategy.tradingHalted = event.params.halted;
    strategy.save();
  }
}
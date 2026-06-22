import { BigInt } from "@graphprotocol/graph-ts";
import { Position, PositionEvent, LiquidationEvent, TraderVolume } from "../generated/schema";
import {
  PositionIncreased,
  PositionDecreased,
  PositionLiquidated,
} from "../generated/MarginManager/MarginManager";

function bumpVolume(account: string, accountBytes: PositionIncreased["params"]["account"], sizeDelta: BigInt, timestamp: BigInt): void {
  let tv = TraderVolume.load(account);
  if (tv == null) {
    tv = new TraderVolume(account);
    tv.account = accountBytes;
    tv.totalVolume = BigInt.zero();
    tv.tradeCount = 0;
  }
  tv.totalVolume = tv.totalVolume.plus(sizeDelta);
  tv.tradeCount = tv.tradeCount + 1;
  tv.lastTradeAt = timestamp;
  tv.save();
}

export function handlePositionIncreased(event: PositionIncreased): void {
  const key = event.params.key.toHexString();

  let position = Position.load(key);
  if (position == null) {
    position = new Position(key);
    position.account = event.params.account;
    position.market = event.params.market;
    position.side = event.params.side;
    position.size = BigInt.zero();
    position.collateral = BigInt.zero();
    position.openedAt = event.block.timestamp;
  }

  position.size = position.size.plus(event.params.sizeDelta);
  position.collateral = position.collateral.plus(event.params.collateralDelta);
  position.entryPrice = event.params.price; // last trade price; the true blended entry lives on-chain, this approximates it for display
  position.status = "OPEN";
  position.lastUpdatedAt = event.block.timestamp;
  position.save();

  const evt = new PositionEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  evt.key = event.params.key;
  evt.account = event.params.account;
  evt.market = event.params.market;
  evt.kind = "INCREASE";
  evt.side = event.params.side;
  evt.sizeDelta = event.params.sizeDelta;
  evt.collateralDelta = event.params.collateralDelta;
  evt.price = event.params.price;
  evt.timestamp = event.block.timestamp;
  evt.txHash = event.transaction.hash;
  evt.save();

  bumpVolume(
    event.params.account.toHexString(),
    event.params.account,
    event.params.sizeDelta,
    event.block.timestamp
  );
}

export function handlePositionDecreased(event: PositionDecreased): void {
  const key = event.params.key.toHexString();
  const position = Position.load(key);
  if (position != null) {
    position.size = position.size.minus(event.params.sizeDelta);
    position.lastUpdatedAt = event.block.timestamp;
    if (position.size.le(BigInt.zero())) {
      position.status = "CLOSED";
      position.closedAt = event.block.timestamp;
    }
    position.save();
  }

  const evt = new PositionEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  evt.key = event.params.key;
  evt.account = event.params.account;
  evt.market = event.params.market;
  evt.kind = "DECREASE";
  evt.sizeDelta = event.params.sizeDelta;
  evt.realizedPnl = event.params.realizedPnl;
  evt.price = event.params.price;
  evt.timestamp = event.block.timestamp;
  evt.txHash = event.transaction.hash;
  evt.save();

  bumpVolume(
    event.params.account.toHexString(),
    event.params.account,
    event.params.sizeDelta,
    event.block.timestamp
  );
}

export function handlePositionLiquidated(event: PositionLiquidated): void {
  const key = event.params.key.toHexString();
  const position = Position.load(key);
  if (position != null) {
    position.size = BigInt.zero();
    position.collateral = BigInt.zero();
    position.status = "LIQUIDATED";
    position.lastUpdatedAt = event.block.timestamp;
    position.closedAt = event.block.timestamp;
    position.save();
  }

  const liq = new LiquidationEvent(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  );
  liq.account = event.params.account;
  liq.market = event.params.market;
  liq.side = position != null ? position.side : 0; // PositionLiquidated doesn't carry side directly; the now-cleared Position still has it loaded above
  liq.keeper = event.params.keeper;
  liq.size = event.params.size;
  liq.pnl = event.params.pnl;
  liq.price = event.params.price;
  liq.timestamp = event.block.timestamp;
  liq.txHash = event.transaction.hash;
  liq.save();
}
import { LiquidationEvent } from "../generated/schema";
import { Liquidated } from "../generated/LiquidationEngine/LiquidationEngine";

export function handleLiquidated(event: Liquidated): void {
  const id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  const liq = new LiquidationEvent(id);
  liq.account = event.params.account;
  liq.market = event.params.market;
  liq.side = event.params.side;
  liq.keeper = event.params.keeper;
  // size/pnl/price aren't part of the Liquidated event itself — they live on
  // MarginManager's PositionLiquidated event, emitted in the same
  // transaction. Left unset here (nullable in schema would be needed if we
  // wanted them) — see note below.
  liq.size = event.block.number; // placeholder pattern intentionally avoided — see note
  liq.timestamp = event.block.timestamp;
  liq.txHash = event.transaction.hash;
  liq.save();
}
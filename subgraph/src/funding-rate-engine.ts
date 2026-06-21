import { FundingUpdate } from "../generated/schema";
import { FundingUpdated } from "../generated/FundingRateEngine/FundingRateEngine";

export function handleFundingUpdated(event: FundingUpdated): void {
  const id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  const update = new FundingUpdate(id);
  update.market = event.params.market;
  update.cumulativeIndex = event.params.cumulativeIndex;
  update.ratePerSecond = event.params.ratePerSecond;
  update.timestamp = event.block.timestamp;
  update.txHash = event.transaction.hash;
  update.save();
}
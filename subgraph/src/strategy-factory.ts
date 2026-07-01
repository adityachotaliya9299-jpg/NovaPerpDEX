import { Address, BigInt } from "@graphprotocol/graph-ts";
import { Strategy } from "../generated/schema";
import { StrategyCreated } from "../generated/StrategyFactory/StrategyFactory";
import { StrategyVault as StrategyVaultContract } from "../generated/StrategyFactory/StrategyVault";
import { StrategyVault as StrategyVaultTemplate } from "../generated/templates";

export function handleStrategyCreated(event: StrategyCreated): void {
  const vaultAddress = event.params.vault;
  const vaultId = vaultAddress.toHexString();

  // Read the vault's risk params directly via contract calls — these are
  // immutable after construction, so a one-time read at creation is correct
  // and avoids needing the constructor args encoded as event params.
  const vaultContract = StrategyVaultContract.bind(vaultAddress);

  const strategy = new Strategy(vaultId);
  strategy.vault = vaultAddress;
  strategy.creator = event.params.creator;
  strategy.name = event.params.name;
  strategy.createdAt = event.block.timestamp;
  strategy.createdTxHash = event.transaction.hash;
  strategy.active = true;
  strategy.tradingHalted = false;
  strategy.totalDeposited = BigInt.zero();
  strategy.totalWithdrawn = BigInt.zero();
  strategy.investorCount = 0;
  strategy.tradeCount = 0;
  strategy.peakNAV = BigInt.zero();
  strategy.currentDrawdownBpsAtLastUpdate = BigInt.zero();

  // Best-effort reads — wrapped individually so one failing call (e.g. if
  // ABI mismatch) doesn't block the whole entity from being created.
  const agentResult = vaultContract.try_agentWallet();
  strategy.agentWallet = agentResult.reverted ? Address.zero() : agentResult.value;

  const thesisResult = vaultContract.try_thesis();
  strategy.thesis = thesisResult.reverted ? "" : thesisResult.value;

  const drawdownResult = vaultContract.try_maxDrawdownBps();
  strategy.maxDrawdownBps = drawdownResult.reverted ? BigInt.zero() : drawdownResult.value;

  const leverageResult = vaultContract.try_maxLeverageBps();
  strategy.maxLeverageBps = leverageResult.reverted ? BigInt.zero() : leverageResult.value;

  const positionResult = vaultContract.try_maxSinglePositionBps();
  strategy.maxSinglePositionBps = positionResult.reverted ? BigInt.zero() : positionResult.value;

  strategy.save();

  // This is the critical step: start watching this newly-deployed vault
  // address for its own events going forward. Without this, only the
  // factory's StrategyCreated event would ever be indexed — none of the
  // vault's own Deposit/Withdraw/AgentTraded events would be seen.
  StrategyVaultTemplate.create(vaultAddress);
}
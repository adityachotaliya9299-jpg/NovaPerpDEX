import { Order } from "../generated/schema";
import {
  OrderPlaced,
  OrderCancelled,
  OrderExecuted,
} from "../generated/OrderBook/OrderBook";

export function handleOrderPlaced(event: OrderPlaced): void {
  const id = event.params.orderId.toString();
  const order = new Order(id);
  order.account = event.params.account;
  order.market = event.params.market;
  order.status = "PLACED";
  order.placedAt = event.block.timestamp;
  order.placedTxHash = event.transaction.hash;
  order.save();
}

export function handleOrderExecuted(event: OrderExecuted): void {
  const id = event.params.orderId.toString();
  const order = Order.load(id);
  if (order == null) return; // event arrived before the placement event was indexed — shouldn't happen given chain ordering, but guard defensively
  order.status = "EXECUTED";
  order.executedAt = event.block.timestamp;
  order.executedPrice = event.params.executionPrice;
  order.executedTxHash = event.transaction.hash;
  order.save();
}

export function handleOrderCancelled(event: OrderCancelled): void {
  const id = event.params.orderId.toString();
  const order = Order.load(id);
  if (order == null) return;
  order.status = "CANCELLED";
  order.cancelledAt = event.block.timestamp;
  order.cancelledTxHash = event.transaction.hash;
  order.save();
}
#include "../include/engine.hpp"

#include <algorithm>
#include <iostream>
#include <limits>

namespace {
std::int64_t notional(std::uint64_t price, std::uint64_t quantity) {
  const auto p = static_cast<__int128>(price);
  const auto q = static_cast<__int128>(quantity);
  const auto value = (p * q) / kScale;
  if (value > std::numeric_limits<std::int64_t>::max()) return std::numeric_limits<std::int64_t>::max();
  return static_cast<std::int64_t>(value);
}
}

void MatchingEngine::deposit_funds(std::uint64_t user_id, std::int64_t amount) {
  if (amount <= 0) return;
  auto& account = accounts_[user_id];
  account.user_id = user_id;
  account.collateral += amount;
}

void MatchingEngine::execute_trade(OrderPacket& incoming, OrderPacket& resting) {
  const auto quantity = std::min(incoming.quantity, resting.quantity);
  incoming.quantity -= quantity;
  resting.quantity -= quantity;
  const auto price = resting.price;

  auto& buyer = accounts_[incoming.side == static_cast<std::uint8_t>(OrderSide::Buy) ? incoming.user_id : resting.user_id];
  auto& seller = accounts_[incoming.side == static_cast<std::uint8_t>(OrderSide::Sell) ? incoming.user_id : resting.user_id];
  buyer.position_size += static_cast<std::int64_t>(quantity);
  buyer.entry_price = price;
  seller.position_size -= static_cast<std::int64_t>(quantity);
  seller.entry_price = price;

  std::cout << "MATCH order=" << incoming.order_id << " resting=" << resting.order_id
            << " quantity=" << quantity << " price=" << price << '\n';
}

void MatchingEngine::process_order(const OrderPacket& input) {
  if (input.order_id == 0 || input.user_id == 0 || input.quantity == 0 ||
      input.side > static_cast<std::uint8_t>(OrderSide::Sell) ||
      input.type > static_cast<std::uint8_t>(OrderType::Market)) return;
  if (input.type == static_cast<std::uint8_t>(OrderType::Market) || input.price == 0) return;

  auto order = input;
  auto& account = accounts_[order.user_id];
  const auto required = notional(order.price, order.quantity) / 20; // demo-only 5% check
  if (account.collateral < required) return;

  if (order.side == static_cast<std::uint8_t>(OrderSide::Buy)) {
    for (std::size_t i = 0; i < ask_count_ && order.quantity > 0; ++i)
      if (asks_[i].quantity > 0 && asks_[i].price <= order.price) execute_trade(order, asks_[i]);
    if (order.quantity > 0 && bid_count_ < bids_.size()) bids_[bid_count_++] = order;
  } else {
    for (std::size_t i = 0; i < bid_count_ && order.quantity > 0; ++i)
      if (bids_[i].quantity > 0 && bids_[i].price >= order.price) execute_trade(order, bids_[i]);
    if (order.quantity > 0 && ask_count_ < asks_.size()) asks_[ask_count_++] = order;
  }
}

void MatchingEngine::check_liquidations(std::uint64_t) {
  // Deliberately no automatic liquidation: production liquidation requires a reviewed
  // risk, insurance-fund, auction, and settlement design, not a balance wipe.
}

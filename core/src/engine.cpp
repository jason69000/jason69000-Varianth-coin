#include "../include/engine.hpp"

#include <algorithm>
#include <atomic>
#include <iostream>
#include <limits>

namespace {
std::int64_t notional(std::uint64_t price, std::uint64_t quantity) {
  const auto value = (static_cast<__int128>(price) * static_cast<__int128>(quantity)) / kScale;
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

std::uint64_t MatchingEngine::level_quantity(std::uint64_t price, std::uint8_t side) const {
  const auto& book = side == static_cast<std::uint8_t>(OrderSide::Buy) ? bids_ : asks_;
  const auto count = side == static_cast<std::uint8_t>(OrderSide::Buy) ? bid_count_ : ask_count_;
  std::uint64_t total = 0;
  for (std::size_t i = 0; i < count; ++i) {
    if (book[i].price == price) total += book[i].quantity;
  }
  return total;
}

void MatchingEngine::publish_depth(std::uint64_t price, std::uint8_t side) {
  if (!shared_memory_) return;
  auto write = std::atomic_ref<std::uint32_t>(shared_memory_->depth_write_index);
  auto read = std::atomic_ref<std::uint32_t>(shared_memory_->depth_read_index);
  const auto current = write.load(std::memory_order_relaxed);
  if (current - read.load(std::memory_order_acquire) >= kQueueCapacity) return;
  shared_memory_->depth_queue[current % kQueueCapacity] = DepthDelta{price, level_quantity(price, side), side, {}};
  write.store(current + 1, std::memory_order_release);
}

void MatchingEngine::execute_trade(OrderPacket& incoming, OrderPacket& resting) {
  const auto quantity = std::min(incoming.quantity, resting.quantity);
  const auto price = resting.price;
  const auto passive_side = resting.side;
  incoming.quantity -= quantity;
  resting.quantity -= quantity;

  auto& buyer = accounts_[incoming.side == static_cast<std::uint8_t>(OrderSide::Buy) ? incoming.user_id : resting.user_id];
  auto& seller = accounts_[incoming.side == static_cast<std::uint8_t>(OrderSide::Sell) ? incoming.user_id : resting.user_id];
  buyer.position_size += static_cast<std::int64_t>(quantity);
  buyer.entry_price = price;
  seller.position_size -= static_cast<std::int64_t>(quantity);
  seller.entry_price = price;

  publish_depth(price, passive_side);
  std::cout << "MATCH order=" << incoming.order_id << " resting=" << resting.order_id
            << " quantity=" << quantity << " price=" << price << '\n';
}

void MatchingEngine::process_order(const OrderPacket& input) {
  if (input.order_id == 0 || input.user_id == 0 || input.quantity == 0 ||
      input.side > static_cast<std::uint8_t>(OrderSide::Sell) ||
      input.type > static_cast<std::uint8_t>(OrderType::Market) ||
      input.type == static_cast<std::uint8_t>(OrderType::Market) || input.price == 0) return;

  auto order = input;
  auto& account = accounts_[order.user_id];
  if (account.collateral < notional(order.price, order.quantity) / 20) return;

  if (order.side == static_cast<std::uint8_t>(OrderSide::Buy)) {
    for (std::size_t i = 0; i < ask_count_ && order.quantity > 0; ++i) {
      if (asks_[i].quantity > 0 && asks_[i].price <= order.price) execute_trade(order, asks_[i]);
    }
    if (order.quantity > 0 && bid_count_ < bids_.size()) {
      bids_[bid_count_++] = order;
      publish_depth(order.price, order.side);
    }
  } else {
    for (std::size_t i = 0; i < bid_count_ && order.quantity > 0; ++i) {
      if (bids_[i].quantity > 0 && bids_[i].price >= order.price) execute_trade(order, bids_[i]);
    }
    if (order.quantity > 0 && ask_count_ < asks_.size()) {
      asks_[ask_count_++] = order;
      publish_depth(order.price, order.side);
    }
  }
}

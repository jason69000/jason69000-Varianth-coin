#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <unordered_map>

constexpr std::size_t kQueueCapacity = 4096;
constexpr std::uint64_t kScale = 100'000'000ULL;

enum class OrderSide : std::uint8_t { Buy = 0, Sell = 1 };
enum class OrderType : std::uint8_t { Limit = 0, Market = 1 };

// ABI shared with gateway/main.go. The trailing padding makes every slot 64 bytes.
struct alignas(64) OrderPacket {
  std::uint64_t order_id;
  std::uint64_t user_id;
  std::uint64_t price;
  std::uint64_t quantity;
  std::uint8_t side;
  std::uint8_t type;
  std::uint8_t reserved[6];
  std::uint8_t slot_padding[24];
};
static_assert(sizeof(OrderPacket) == 64);

struct SharedBuffer {
  std::uint32_t write_index;
  std::uint32_t read_index;
  std::uint8_t header_padding[56];
  std::array<OrderPacket, kQueueCapacity> queue;
};
static_assert(offsetof(SharedBuffer, queue) == 64);

struct Account {
  std::uint64_t user_id{};
  std::int64_t collateral{};
  std::int64_t position_size{};
  std::uint64_t entry_price{};
};

class MatchingEngine {
 public:
  void deposit_funds(std::uint64_t user_id, std::int64_t amount);
  void process_order(const OrderPacket& order);
  void check_liquidations(std::uint64_t mark_price);

 private:
  void execute_trade(OrderPacket& incoming, OrderPacket& resting);
  std::unordered_map<std::uint64_t, Account> accounts_;
  std::array<OrderPacket, 10000> bids_{};
  std::array<OrderPacket, 10000> asks_{};
  std::size_t bid_count_{};
  std::size_t ask_count_{};
};

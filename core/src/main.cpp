#include "../include/engine.hpp"

#include <atomic>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

int main() {
  constexpr const char* name = "/varianth_exchange_shm";
  const int fd = shm_open(name, O_CREAT | O_RDWR, 0600);
  if (fd < 0 || ftruncate(fd, sizeof(SharedBuffer)) != 0) return 1;
  auto* buffer = static_cast<SharedBuffer*>(mmap(nullptr, sizeof(SharedBuffer), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0));
  if (buffer == MAP_FAILED) return 1;
  std::memset(buffer, 0, sizeof(SharedBuffer));

  MatchingEngine engine;
  engine.deposit_funds(1001, 500'000'000);
  engine.deposit_funds(1002, 500'000'000);
  std::cout << "engine ready\n";

  for (;;) {
    const auto read = std::atomic_ref<std::uint32_t>(buffer->read_index);
    const auto write = std::atomic_ref<std::uint32_t>(buffer->write_index);
    if (read.load(std::memory_order_acquire) != write.load(std::memory_order_acquire)) {
      const auto index = read.load(std::memory_order_relaxed) % kQueueCapacity;
      const auto order = buffer->queue[index];
      read.fetch_add(1, std::memory_order_release);
      engine.process_order(order);
    } else {
      usleep(1000);
    }
  }
}

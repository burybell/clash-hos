#pragma once

#include <cstdint>
#include <string>

namespace clash_hos {

struct CoreStatus {
  bool available;
  bool running;
  int runtime_abi;
  std::string message;
};

struct TrafficStats {
  uint64_t upload_bytes;
  uint64_t download_bytes;
  uint64_t active_connections;
};

class CoreRuntime final {
 public:
  static CoreRuntime& Instance();

  CoreStatus GetStatus() const;
  CoreStatus Start(const std::string& config, const std::string& work_dir,
                   int tun_fd);
  CoreStatus Stop();
  TrafficStats GetTrafficStats() const;

 private:
  CoreRuntime() = default;
};

}  // namespace clash_hos

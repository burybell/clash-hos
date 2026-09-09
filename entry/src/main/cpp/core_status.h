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
  uint64_t inbound_packets;
  uint64_t outbound_packets;
  uint64_t dropped_packets;
  uint64_t tcp_open_errors;
  uint64_t udp_open_errors;
  uint64_t udp_quic_blocked_packets;
  uint64_t udp_vision_rejections;
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

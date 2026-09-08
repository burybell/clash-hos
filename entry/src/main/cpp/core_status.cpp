#include "core_status.h"

#include <dlfcn.h>
#include <unistd.h>

#include <chrono>
#include <string>
#include <thread>

namespace clash_hos {

namespace {

using StartWithTunFn = char* (*)(const char*, const char*, const char*, int);
using IsRunningFn = int (*)(void);
using ShutdownFn = int (*)(void);
using FreeStringFn = void (*)(char*);
using XrayNewFn = void* (*)(void**);
using XrayLoadConfigFn = int (*)(void*, const char*, void**);
using XraySetTunFdFn = int (*)(void*, int, int, int, void**);
using XraySetRuntimeProfileFn = int (*)(void*, int, void**);
using XrayStartFn = int (*)(void*, void**);
using XrayStopFn = int (*)(void*, void**);
using XrayFreeFn = void (*)(void*);
using XrayErrorMessageFn = const char* (*)(const void*);
using XrayErrorFreeFn = void (*)(void*);

struct XrayTunStatsV1 {
  size_t struct_size;
  uint64_t inbound_packets;
  uint64_t outbound_packets;
  uint64_t dropped_packets;
  uint64_t inbound_dropped_packets;
  uint64_t outbound_dropped_packets;
  uint64_t tcp_stack_to_remote_bytes;
  uint64_t tcp_remote_written_bytes;
  uint64_t tcp_remote_read_bytes;
  uint64_t tcp_backpressure_events;
  uint64_t tcp_stack_to_remote_backpressure_events;
  uint64_t tcp_remote_to_stack_backpressure_events;
  uint64_t tcp_remote_write_batches;
  uint64_t tcp_remote_write_batch_messages;
  uint64_t tcp_remote_write_batch_max_messages;
  uint64_t tcp_remote_write_batch_max_bytes;
  uint64_t tcp_remote_write_wait_events;
  uint64_t tcp_remote_write_wait_ms_total;
  uint64_t tcp_remote_write_wait_ms_max;
  uint64_t tcp_remote_flush_wait_events;
  uint64_t tcp_remote_flush_wait_ms_total;
  uint64_t tcp_remote_flush_wait_ms_max;
  uint64_t tcp_pending_remote_bytes;
  uint64_t tcp_pending_remote_flows;
  uint64_t tcp_pending_remote_max_bytes;
  uint64_t tcp_pending_upload_bytes;
  uint64_t tcp_pending_upload_max_bytes;
  uint64_t tcp_pending_total_bytes;
  uint64_t tcp_remote_buffer_limit_bytes;
  uint64_t tcp_buffer_hard_limit_bytes;
  uint64_t tcp_remote_buffer_pressure_active;
  uint64_t tcp_remote_write_errors;
  uint64_t tcp_remote_closed_events;
  uint64_t tcp_remote_read_errors;
  uint64_t tcp_open_errors;
  uint64_t tcp_open_events;
  uint64_t tcp_open_duration_ms_total;
  uint64_t tcp_open_duration_ms_max;
  uint64_t tcp_first_byte_events;
  uint64_t tcp_first_byte_duration_ms_total;
  uint64_t tcp_first_byte_duration_ms_max;
  uint64_t tcp443_open_events;
  uint64_t tcp443_open_duration_ms_total;
  uint64_t tcp443_open_duration_ms_max;
  uint64_t tcp443_first_byte_events;
  uint64_t tcp443_first_byte_duration_ms_total;
  uint64_t tcp443_first_byte_duration_ms_max;
  uint64_t active_tcp_flows;
  uint64_t active_udp_flows;
  uint64_t udp_flow_limit;
  uint64_t udp_budget_drops;
  uint64_t udp_evicted_flows;
  uint64_t udp_channel_dropped_packets;
  uint64_t udp_remote_open_events;
  uint64_t udp_remote_udp443_open_events;
  uint64_t udp_remote_written_bytes;
  uint64_t udp_remote_read_bytes;
  uint64_t udp_open_errors;
  uint64_t udp_vision_udp443_rejections;
  uint64_t udp_remote_write_errors;
  uint64_t udp_remote_read_errors;
  uint64_t udp_remote_closed_events;
  uint64_t udp_quic_blocked_packets;
  uint64_t inbound_queue_depth;
  uint64_t outbound_queue_depth;
  uint64_t inbound_queue_max_packets;
  uint64_t outbound_queue_max_packets;
  uint64_t tun_fd_write_batches;
  uint64_t tun_fd_write_batch_packets;
  uint64_t tun_fd_write_batch_max_packets;
  uint64_t tun_fd_read_loop_exits;
  uint64_t tun_fd_write_loop_exits;
  uint64_t tun_fd_transient_io_errors;
};

using XrayTunStatsFn = int (*)(void*, XrayTunStatsV1*, void**);

struct RuntimeProbeResult {
  int abi = 0;
  StartWithTunFn start_with_tun = nullptr;
  IsRunningFn is_running = nullptr;
  ShutdownFn shutdown = nullptr;
  FreeStringFn free_string = nullptr;
  std::string message;

  bool Available() const {
    return abi == 1 && start_with_tun != nullptr && is_running != nullptr &&
           shutdown != nullptr && free_string != nullptr;
  }
};

struct XrayRuntimeResult {
  int abi = 0;
  XrayNewFn create = nullptr;
  XrayLoadConfigFn load_config = nullptr;
  XraySetTunFdFn set_tun_fd = nullptr;
  XraySetRuntimeProfileFn set_runtime_profile = nullptr;
  XrayStartFn start = nullptr;
  XrayStopFn stop = nullptr;
  XrayFreeFn free = nullptr;
  XrayErrorMessageFn error_message = nullptr;
  XrayErrorFreeFn error_free = nullptr;
  XrayTunStatsFn tun_stats = nullptr;
  void* handle = nullptr;
  bool running = false;
  std::string message;

  bool Available() const {
    return abi == 1 && create != nullptr && load_config != nullptr &&
           set_tun_fd != nullptr && start != nullptr && stop != nullptr &&
           free != nullptr && error_message != nullptr && error_free != nullptr;
  }
};

XrayRuntimeResult LoadXrayRuntime() {
  void* handle = dlopen("libxray_ffi.so", RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    return {.message = "xray-rust Reality 内核未打包"};
  }
  XrayRuntimeResult result;
  auto version = reinterpret_cast<unsigned int (*)(void)>(
      dlsym(handle, "xray_ffi_version_major"));
  result.abi = version == nullptr ? 0 : static_cast<int>(version());
  result.create = reinterpret_cast<XrayNewFn>(dlsym(handle, "xray_core_new"));
  result.load_config = reinterpret_cast<XrayLoadConfigFn>(
      dlsym(handle, "xray_core_load_config_json"));
  result.set_tun_fd = reinterpret_cast<XraySetTunFdFn>(
      dlsym(handle, "xray_core_set_tun_fd"));
  result.set_runtime_profile = reinterpret_cast<XraySetRuntimeProfileFn>(
      dlsym(handle, "xray_core_set_tun_runtime_profile"));
  result.start = reinterpret_cast<XrayStartFn>(dlsym(handle, "xray_core_start"));
  result.stop = reinterpret_cast<XrayStopFn>(dlsym(handle, "xray_core_stop"));
  result.free = reinterpret_cast<XrayFreeFn>(dlsym(handle, "xray_core_free"));
  result.error_message = reinterpret_cast<XrayErrorMessageFn>(
      dlsym(handle, "xray_error_message"));
  result.error_free = reinterpret_cast<XrayErrorFreeFn>(
      dlsym(handle, "xray_error_free"));
  result.tun_stats = reinterpret_cast<XrayTunStatsFn>(
      dlsym(handle, "xray_tun_stats"));
  result.message = result.Available() ? "xray-rust Reality 内核已就绪"
                                      : "xray-rust C ABI 不完整";
  return result;
}

XrayRuntimeResult& GetXrayRuntime() {
  static XrayRuntimeResult result = LoadXrayRuntime();
  return result;
}

std::string TakeXrayError(XrayRuntimeResult& runtime, void* error,
                          const std::string& fallback) {
  if (error == nullptr) {
    return fallback;
  }
  const char* message = runtime.error_message(error);
  const std::string result = message == nullptr ? fallback : message;
  runtime.error_free(error);
  return result;
}

void ResetXrayHandle(XrayRuntimeResult& runtime) {
  if (runtime.handle != nullptr) {
    runtime.free(runtime.handle);
    runtime.handle = nullptr;
  }
  runtime.running = false;
}

CoreStatus StartXray(XrayRuntimeResult& runtime, const std::string& config,
                     int tun_fd) {
  if (!runtime.Available()) {
    return {false, false, runtime.abi, runtime.message};
  }
  if (runtime.running) {
    return {true, true, runtime.abi, "Reality 内核正在运行"};
  }
  const int owned_fd = dup(tun_fd);
  if (owned_fd < 0) {
    return {true, false, runtime.abi, "无法复制 TUN 文件描述符"};
  }

  void* error = nullptr;
  runtime.handle = runtime.create(&error);
  if (runtime.handle == nullptr) {
    close(owned_fd);
    return {true, false, runtime.abi,
            "Reality 内核初始化失败：" +
                TakeXrayError(runtime, error, "未知错误")};
  }
  if (runtime.set_tun_fd(runtime.handle, owned_fd, 0, 1, &error) != 0) {
    const std::string message = TakeXrayError(runtime, error, "TUN 接入失败");
    close(owned_fd);
    ResetXrayHandle(runtime);
    return {true, false, runtime.abi, "Reality " + message};
  }
  if (runtime.set_runtime_profile != nullptr &&
      runtime.set_runtime_profile(runtime.handle, 1, &error) != 0) {
    const std::string message = TakeXrayError(runtime, error, "性能模式设置失败");
    ResetXrayHandle(runtime);
    return {true, false, runtime.abi, "Reality " + message};
  }
  if (runtime.load_config(runtime.handle, config.c_str(), &error) != 0) {
    const std::string message = TakeXrayError(runtime, error, "配置加载失败");
    ResetXrayHandle(runtime);
    return {true, false, runtime.abi, "Reality 配置错误：" + message};
  }
  if (runtime.start(runtime.handle, &error) != 0) {
    const std::string message = TakeXrayError(runtime, error, "启动失败");
    ResetXrayHandle(runtime);
    return {true, false, runtime.abi, "Reality 启动失败：" + message};
  }
  runtime.running = true;
  return {true, true, runtime.abi, "Reality 内核正在运行"};
}

RuntimeProbeResult LoadRuntimeProbe() {
  void* rust_handle =
      dlopen("libclash_hos_rust_spike.so", RTLD_NOW | RTLD_LOCAL);
  if (rust_handle == nullptr) {
    return {.message = "OHOS 原生运行时不可用，VPN 已保持安全禁用"};
  }

  dlerror();
  auto probe = reinterpret_cast<int (*)(void)>(
      dlsym(rust_handle, "clash_hos_rust_probe_abi_version"));
  if (dlerror() != nullptr || probe == nullptr) {
    return {.message = "OHOS 原生运行时探针符号不可用"};
  }

  RuntimeProbeResult result;
  result.abi = probe();
  if (result.abi != 1) {
    result.message = "OHOS 原生运行时 ABI 不匹配";
    return result;
  }

  void* clash_handle = dlopen("libclashrs.so", RTLD_NOW | RTLD_LOCAL);
  if (clash_handle == nullptr) {
    result.message = "OHOS 原生运行时已就绪，但未打包 ClashRS 内核";
    return result;
  }

  dlerror();
  result.start_with_tun = reinterpret_cast<StartWithTunFn>(
      dlsym(clash_handle, "clash_start_with_tun_fd"));
  result.is_running =
      reinterpret_cast<IsRunningFn>(dlsym(clash_handle, "clash_is_running"));
  result.shutdown =
      reinterpret_cast<ShutdownFn>(dlsym(clash_handle, "clash_shutdown"));
  result.free_string = reinterpret_cast<FreeStringFn>(
      dlsym(clash_handle, "clash_free_string"));
  const char* symbol_error = dlerror();
  if (symbol_error != nullptr || !result.Available()) {
    result.message = "ClashRS 已加载，但生命周期接口不完整";
    return result;
  }

  result.message = "ClashRS 鸿蒙内核已就绪";
  return result;
}

RuntimeProbeResult& GetRuntimeProbeResult() {
  // Keep both Rust shared libraries loaded for the application lifetime.
  static RuntimeProbeResult result = LoadRuntimeProbe();
  return result;
}

CoreStatus StatusFromRuntime(const RuntimeProbeResult& runtime,
                             const std::string& idle_message) {
  const bool running = runtime.Available() && runtime.is_running() != 0;
  return {
      .available = runtime.Available(),
      .running = running,
      .runtime_abi = runtime.abi,
      .message = running ? "ClashRS 内核正在运行" : idle_message,
  };
}

}  // namespace

CoreRuntime& CoreRuntime::Instance() {
  static CoreRuntime runtime;
  return runtime;
}

CoreStatus CoreRuntime::GetStatus() const {
  XrayRuntimeResult& xray = GetXrayRuntime();
  if (xray.Available()) {
    return {
        .available = true,
        .running = xray.running,
        .runtime_abi = xray.abi,
        .message = xray.running ? "Reality 内核正在运行" : xray.message,
    };
  }
  RuntimeProbeResult& runtime = GetRuntimeProbeResult();
  return StatusFromRuntime(runtime, runtime.message);
}

CoreStatus CoreRuntime::Start(const std::string& config,
                              const std::string& work_dir, int tun_fd) {
  const size_t first = config.find_first_not_of(" \t\r\n");
  if (first != std::string::npos && config[first] == '{') {
    return StartXray(GetXrayRuntime(), config, tun_fd);
  }
  RuntimeProbeResult& runtime = GetRuntimeProbeResult();
  if (!runtime.Available()) {
    return StatusFromRuntime(runtime, runtime.message);
  }
  if (config.empty() || work_dir.empty() || tun_fd < 0) {
    return StatusFromRuntime(runtime, "启动参数无效");
  }
  if (runtime.is_running() != 0) {
    return StatusFromRuntime(runtime, "ClashRS 内核正在运行");
  }

  const int owned_fd = dup(tun_fd);
  if (owned_fd < 0) {
    return StatusFromRuntime(runtime, "无法复制 TUN 文件描述符");
  }

  const std::string log_path = work_dir + "/clashrs.log";
  char* error = runtime.start_with_tun(config.c_str(), log_path.c_str(),
                                       work_dir.c_str(), owned_fd);
  const std::string error_message = error == nullptr ? "FFI 未返回结果" : error;
  if (error != nullptr) {
    runtime.free_string(error);
  }
  if (!error_message.empty()) {
    close(owned_fd);
    return StatusFromRuntime(runtime, "内核启动失败：" + error_message);
  }

  // Configuration parsing is synchronous; allow the TUN runner to initialize
  // before advertising readiness to the VPN Extension.
  std::this_thread::sleep_for(std::chrono::milliseconds(250));
  if (runtime.is_running() == 0) {
    return StatusFromRuntime(runtime, "内核启动后意外退出，请查看 ClashRS 日志");
  }
  return StatusFromRuntime(runtime, "ClashRS 内核正在运行");
}

CoreStatus CoreRuntime::Stop() {
  XrayRuntimeResult& xray = GetXrayRuntime();
  if (xray.running && xray.handle != nullptr) {
    void* error = nullptr;
    const int status = xray.stop(xray.handle, &error);
    const std::string message = status == 0
        ? "Reality 内核已停止"
        : "Reality 停止失败：" + TakeXrayError(xray, error, "未知错误");
    ResetXrayHandle(xray);
    return {true, false, xray.abi, message};
  }
  RuntimeProbeResult& runtime = GetRuntimeProbeResult();
  if (!runtime.Available()) {
    return StatusFromRuntime(runtime, runtime.message);
  }
  if (runtime.is_running() != 0) {
    runtime.shutdown();
  }
  return StatusFromRuntime(runtime, "ClashRS 内核已停止");
}

TrafficStats CoreRuntime::GetTrafficStats() const {
  XrayRuntimeResult& xray = GetXrayRuntime();
  if (!xray.running || xray.handle == nullptr || xray.tun_stats == nullptr) {
    return {0, 0, 0};
  }
  XrayTunStatsV1 stats{};
  stats.struct_size = sizeof(stats);
  void* error = nullptr;
  if (xray.tun_stats(xray.handle, &stats, &error) != 0) {
    if (error != nullptr) {
      xray.error_free(error);
    }
    return {0, 0, 0};
  }
  return {
      stats.tcp_remote_written_bytes + stats.udp_remote_written_bytes,
      stats.tcp_remote_read_bytes + stats.udp_remote_read_bytes,
      stats.active_tcp_flows + stats.active_udp_flows,
  };
}

}  // namespace clash_hos

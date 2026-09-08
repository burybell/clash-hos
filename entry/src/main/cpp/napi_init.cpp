#include <hilog/log.h>
#include <napi/native_api.h>

#include <dlfcn.h>

#include <string>
#include <vector>

#include "core_status.h"

namespace {

constexpr unsigned int kLogDomain = 0xC105;
constexpr char kLogTag[] = "ClashCoreBridge";

struct CompatibilityProbeResult {
  bool ready;
  std::string message;
};

CompatibilityProbeResult ProbeCompatibilityCoreLibrary() {
  void* handle = dlopen("libxray_ffi.so", RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    const char* error = dlerror();
    return {false, error == nullptr ? "共享库加载失败" : error};
  }
  dlerror();
  auto probe = reinterpret_cast<unsigned int (*)(void)>(
      dlsym(handle, "xray_ffi_version_major"));
  const char* symbol_error = dlerror();
  if (symbol_error != nullptr || probe == nullptr) {
    return {false, symbol_error == nullptr ? "兼容层 ABI 接口缺失" : symbol_error};
  }
  const bool ready = probe() == 1;
  return {ready, ready ? "xray-rust Reality 内核已就绪" : "兼容层 ABI 不匹配"};
}

const CompatibilityProbeResult& GetCompatibilityProbeResult() {
  static const CompatibilityProbeResult result = ProbeCompatibilityCoreLibrary();
  return result;
}

napi_value ToNapiStatus(napi_env env, const clash_hos::CoreStatus& status) {
  napi_value result = nullptr;
  napi_create_object(env, &result);

  napi_value available = nullptr;
  napi_get_boolean(env, status.available, &available);
  napi_set_named_property(env, result, "available", available);

  napi_value running = nullptr;
  napi_get_boolean(env, status.running, &running);
  napi_set_named_property(env, result, "running", running);

  napi_value runtime_abi = nullptr;
  napi_create_int32(env, status.runtime_abi, &runtime_abi);
  napi_set_named_property(env, result, "runtimeAbi", runtime_abi);

  napi_value message = nullptr;
  napi_create_string_utf8(env, status.message.c_str(), status.message.size(), &message);
  napi_set_named_property(env, result, "message", message);

  return result;
}

std::string GetString(napi_env env, napi_value value) {
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
    return {};
  }
  std::vector<char> buffer(length + 1, '\0');
  if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(),
                                 &length) != napi_ok) {
    return {};
  }
  return std::string(buffer.data(), length);
}

napi_value GetStatus(napi_env env, napi_callback_info info) {
  (void)info;
  return ToNapiStatus(env, clash_hos::CoreRuntime::Instance().GetStatus());
}

napi_value Start(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 3) {
    return ToNapiStatus(env, {
        .available = true,
        .running = false,
        .runtime_abi = 1,
        .message = "启动参数数量无效",
    });
  }

  int32_t tun_fd = -1;
  napi_get_value_int32(env, argv[2], &tun_fd);
  const clash_hos::CoreStatus status = clash_hos::CoreRuntime::Instance().Start(
      GetString(env, argv[0]), GetString(env, argv[1]), tun_fd);
  OH_LOG_INFO(LOG_APP, "Clash core start requested, running=%{public}d",
              status.running);
  return ToNapiStatus(env, status);
}

napi_value Stop(napi_env env, napi_callback_info info) {
  (void)info;
  const clash_hos::CoreStatus status =
      clash_hos::CoreRuntime::Instance().Stop();
  OH_LOG_INFO(LOG_APP, "Clash core stop requested, running=%{public}d",
              status.running);
  return ToNapiStatus(env, status);
}

napi_value ProbeCompatibilityCore(napi_env env, napi_callback_info info) {
  (void)info;
  napi_value result = nullptr;
  napi_get_boolean(env, GetCompatibilityProbeResult().ready, &result);
  return result;
}

napi_value GetCompatibilityCoreStatus(napi_env env, napi_callback_info info) {
  (void)info;
  const std::string& message = GetCompatibilityProbeResult().message;
  napi_value result = nullptr;
  napi_create_string_utf8(env, message.c_str(), message.size(), &result);
  return result;
}

napi_value GetTrafficStats(napi_env env, napi_callback_info info) {
  (void)info;
  const clash_hos::TrafficStats stats =
      clash_hos::CoreRuntime::Instance().GetTrafficStats();
  napi_value result = nullptr;
  napi_create_object(env, &result);
  napi_value upload = nullptr;
  napi_create_double(env, static_cast<double>(stats.upload_bytes), &upload);
  napi_set_named_property(env, result, "uploadBytes", upload);
  napi_value download = nullptr;
  napi_create_double(env, static_cast<double>(stats.download_bytes), &download);
  napi_set_named_property(env, result, "downloadBytes", download);
  napi_value connections = nullptr;
  napi_create_double(env, static_cast<double>(stats.active_connections), &connections);
  napi_set_named_property(env, result, "activeConnections", connections);
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"probeCompatibilityCore", nullptr, ProbeCompatibilityCore, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"getCompatibilityCoreStatus", nullptr, GetCompatibilityCoreStatus, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"getTrafficStats", nullptr, GetTrafficStats, nullptr, nullptr, nullptr,
       napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  OH_LOG_INFO(LOG_APP, "Clash core bridge initialized");
  return exports;
}

}  // namespace

EXTERN_C_START
static napi_module clashCoreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "clash_core",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};
EXTERN_C_END

extern "C" __attribute__((constructor)) void RegisterClashCoreModule() {
  napi_module_register(&clashCoreModule);
}

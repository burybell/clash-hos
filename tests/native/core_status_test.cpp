#include <cstdlib>
#include <iostream>

#include "core_status.h"

namespace {

void Require(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAILED: " << message << '\n';
    std::exit(EXIT_FAILURE);
  }
}

}  // namespace

int main() {
  clash_hos::CoreRuntime& first = clash_hos::CoreRuntime::Instance();
  clash_hos::CoreRuntime& second = clash_hos::CoreRuntime::Instance();
  Require(&first == &second, "CoreRuntime must be a singleton");

  const clash_hos::CoreStatus status = first.GetStatus();
  Require(!status.available, "M0 core must fail closed before Mihomo is linked");
  Require(!status.running, "Unavailable core cannot report running");
  Require(!status.message.empty(), "Unavailable core must expose a diagnostic message");

  std::cout << "PASS: native core boundary fails closed\n";
  return EXIT_SUCCESS;
}

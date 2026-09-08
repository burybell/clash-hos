package main

/*
#include <stdint.h>
*/
import "C"

// ClashHosProbeAbiVersion verifies that an OHOS process can load and call a
// Go c-shared library through a stable C ABI.
//
//export ClashHosProbeAbiVersion
func ClashHosProbeAbiVersion() C.int32_t {
	return 1
}

func main() {}

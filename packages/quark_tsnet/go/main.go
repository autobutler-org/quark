// Command quark_tsnet is the C library the Flutter app loads with dart:ffi
// (#1881). Build it with -buildmode=c-archive (iOS) or -buildmode=c-shared
// (everything else); packages/quark_tsnet/hook/build.dart does both.
//
// The C API is three calls over package bridge:
//
//	int   quark_tsnet_start(stateDir, controlUrl, authKey, hostname, upstream)
//	void  quark_tsnet_stop(void)
//	char* quark_tsnet_status(void)   // JSON; free with quark_tsnet_free
//
// quark_tsnet_start blocks until the node is up, so call it off the UI
// isolate. It returns the loopback proxy port, or -1 with the reason in
// status().error.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"unsafe"

	"github.com/autobutler-org/quark/packages/quark_tsnet/go/bridge"
)

//export quark_tsnet_start
func quark_tsnet_start(stateDir, controlURL, authKey, hostname, upstream *C.char) C.int {
	p, err := bridge.Start(bridge.Config{
		StateDir:   C.GoString(stateDir),
		ControlURL: C.GoString(controlURL),
		AuthKey:    C.GoString(authKey),
		Hostname:   C.GoString(hostname),
		Upstream:   C.GoString(upstream),
	})
	if err != nil {
		return -1
	}
	return C.int(p)
}

//export quark_tsnet_stop
func quark_tsnet_stop() {
	_ = bridge.Stop()
}

//export quark_tsnet_status
func quark_tsnet_status() *C.char {
	b, err := json.Marshal(bridge.CurrentStatus())
	if err != nil {
		b = []byte(`{"state":"Stopped","tailnetIPs":[],"port":0,"error":"status encoding failed"}`)
	}
	return C.CString(string(b))
}

//export quark_tsnet_free
func quark_tsnet_free(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}

package main

// #include <stdlib.h>
import "C"

import "unsafe"

func goString(p *C.char) string {
	if p == nil {
		return ""
	}
	return C.GoString(p)
}

//export quark_tsnet_start
func quark_tsnet_start(stateDir, controlURL, authKey, hostname, upstream *C.char) C.int {
	port, _, err := Start(Config{
		StateDir:   goString(stateDir),
		ControlURL: goString(controlURL),
		AuthKey:    goString(authKey),
		Hostname:   goString(hostname),
		Upstream:   goString(upstream),
	})
	if err != nil {
		return -1
	}
	return C.int(port)
}

// quark_tsnet_token returns the token the proxy asks for in
// X-Quark-Tunnel-Token, empty when it is stopped. Free it with
// quark_tsnet_free.
//
//export quark_tsnet_token
func quark_tsnet_token() *C.char {
	return C.CString(Token())
}

//export quark_tsnet_stop
func quark_tsnet_stop() {
	_ = Stop()
}

//export quark_tsnet_status
func quark_tsnet_status() *C.char {
	return C.CString(statusJSON())
}

//export quark_tsnet_free
func quark_tsnet_free(p *C.char) {
	C.free(unsafe.Pointer(p))
}

// quark_tsnet_peer_status returns the Quark peer's current path (direct or
// relayed), recent path changes, and recent request timings, as JSON
// (#3883). It holds no keys, tokens or full addresses. Free it with
// quark_tsnet_free.
//
//export quark_tsnet_peer_status
func quark_tsnet_peer_status() *C.char {
	return C.CString(peerStatusJSON())
}

// quark_tsnet_ping pings the Quark count times inside the tunnel and over
// TCP through it, and returns the round-trip times and the path as JSON
// (#3883). It blocks for up to a few seconds per ping. Free the result with
// quark_tsnet_free.
//
//export quark_tsnet_ping
func quark_tsnet_ping(count C.int) *C.char {
	return C.CString(pingJSON(int(count)))
}

// Standalone harness that links against the shared library through cgo
// and exercises the full lt_* API. Used as a smoke test before we wire
// Dart FFI on top — if this works, the Flutter side will too.
//
// Usage:
//   ./test_runner <magnet>
//
// It boots a session, adds the magnet, waits up to 60s for metadata,
// asks for the stream URL of file [0], and prints HEAD info from it.

package main

/*
#cgo LDFLAGS: -L${SRCDIR}/.. -llibrefy_torrent -Wl,-rpath,${SRCDIR}/..
#include <stdlib.h>
#include "../liblibrefy_torrent.h"
*/
import "C"

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
	"unsafe"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: test_runner <magnet>")
		os.Exit(2)
	}

	cacheDir := C.CString("/tmp/librefy-cli-cache")
	defer C.free(unsafe.Pointer(cacheDir))

	sid := C.lt_create(cacheDir, 0)
	if sid < 0 {
		fail("lt_create")
	}
	defer C.lt_destroy(sid)
	fmt.Printf("session: %d\n", sid)

	magnet := C.CString(os.Args[1])
	defer C.free(unsafe.Pointer(magnet))

	h := C.lt_add_magnet(sid, magnet)
	if h < 0 {
		fail("lt_add_magnet")
	}
	fmt.Printf("handle:  %d\n", h)
	fmt.Println("waiting for metadata (60s)...")

	n := C.lt_wait_metadata(sid, h, 60000)
	if n < 0 {
		fail("lt_wait_metadata")
	}
	fmt.Printf("files:   %d\n", n)

	urlPtr := C.lt_stream_url(sid, h, 0)
	if urlPtr == nil {
		fail("lt_stream_url")
	}
	url := C.GoString(urlPtr)
	C.lt_free_cstring(urlPtr)
	fmt.Printf("URL:     %s\n", url)

	stats := make([]byte, 1024)
	written := C.lt_stats_json(sid, h, (*C.char)(unsafe.Pointer(&stats[0])), C.int(len(stats)))
	fmt.Printf("stats:   %s\n", string(stats[:written]))

	// Now actually hit the URL and print HEAD.
	for try := 0; try < 5; try++ {
		req, _ := http.NewRequest("HEAD", url, nil)
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			fmt.Printf("HEAD %d  Content-Length=%s  Content-Type=%s\n",
				resp.StatusCode,
				resp.Header.Get("Content-Length"),
				resp.Header.Get("Content-Type"))
			_, _ = io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			break
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func fail(where string) {
	errPtr := C.lt_last_error()
	if errPtr != nil {
		err := C.GoString(errPtr)
		C.lt_free_cstring(errPtr)
		fmt.Fprintf(os.Stderr, "%s: %s\n", where, err)
	} else {
		fmt.Fprintf(os.Stderr, "%s: (no error info)\n", where)
	}
	os.Exit(1)
}

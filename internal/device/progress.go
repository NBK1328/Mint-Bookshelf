package device

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"sync"
	"sync/atomic"
	"unsafe"
)

var progressMu sync.Mutex
var progressSeq uint64
var progressCallbacks = map[uint64]func(uint64, uint64) bool{}

//export kmProgress
func kmProgress(sent C.uint64_t, total C.uint64_t, data unsafe.Pointer) C.int {
	if data == nil {
		return 0
	}
	id := uint64(*(*C.uint64_t)(data))
	progressMu.Lock()
	callback := progressCallbacks[id]
	progressMu.Unlock()
	if callback == nil {
		return 0
	}
	if callback(uint64(sent), uint64(total)) {
		return 1
	}
	return 0
}

func registerProgress(callback func(uint64, uint64) bool) (unsafe.Pointer, func()) {
	id := atomic.AddUint64(&progressSeq, 1)
	progressMu.Lock()
	progressCallbacks[id] = callback
	progressMu.Unlock()

	data := C.malloc(C.size_t(unsafe.Sizeof(C.uint64_t(0))))
	*(*C.uint64_t)(data) = C.uint64_t(id)
	return data, func() {
		progressMu.Lock()
		delete(progressCallbacks, id)
		progressMu.Unlock()
		C.free(data)
	}
}

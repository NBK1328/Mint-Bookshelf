package mtp

/*
#cgo CFLAGS: -I/opt/homebrew/include
#cgo LDFLAGS: -L/opt/homebrew/lib -lmtp -lusb-1.0
#include <stdlib.h>
#include <libmtp.h>
*/
import "C"

import (
	"fmt"
	"unsafe"
)

type Device struct {
	Bus       int
	DevNum    int
	VendorID  uint16
	ProductID uint16
	Vendor    string
	Product   string
}

func Init() { C.LIBMTP_Init() }

func Detect() ([]Device, error) {
	var raw *C.LIBMTP_raw_device_t
	var n C.int
	ret := C.LIBMTP_Detect_Raw_Devices(&raw, &n)
	if ret != C.LIBMTP_ERROR_NONE && ret != C.LIBMTP_ERROR_NO_DEVICE_ATTACHED {
		return nil, fmt.Errorf("detect failed: %d", int(ret))
	}
	if n == 0 || raw == nil {
		return nil, nil
	}
	defer C.free(unsafe.Pointer(raw))
	out := make([]Device, 0, int(n))
	base := unsafe.Pointer(raw)
	sz := unsafe.Sizeof(*raw)
	for i := 0; i < int(n); i++ {
		d := (*C.LIBMTP_raw_device_t)(unsafe.Pointer(uintptr(base) + uintptr(i)*sz))
		dev := Device{
			Bus:       int(d.bus_location),
			DevNum:    int(d.devnum),
			VendorID:  uint16(d.device_entry.vendor_id),
			ProductID: uint16(d.device_entry.product_id),
		}
		if d.device_entry.vendor != nil {
			dev.Vendor = C.GoString(d.device_entry.vendor)
		}
		if d.device_entry.product != nil {
			dev.Product = C.GoString(d.device_entry.product)
		}
		out = append(out, dev)
	}
	return out, nil
}

func Open(dev Device) (*C.LIBMTP_mtpdevice_t, error) {
	// Re-detect to get raw handle; simpler: find by bus/dev
	var raw *C.LIBMTP_raw_device_t
	var n C.int
	ret := C.LIBMTP_Detect_Raw_Devices(&raw, &n)
	if ret != C.LIBMTP_ERROR_NONE {
		return nil, fmt.Errorf("detect failed: %d", int(ret))
	}
	defer C.free(unsafe.Pointer(raw))
	base := unsafe.Pointer(raw)
	sz := unsafe.Sizeof(*raw)
	for i := 0; i < int(n); i++ {
		d := (*C.LIBMTP_raw_device_t)(unsafe.Pointer(uintptr(base) + uintptr(i)*sz))
		if int(d.bus_location) == dev.Bus && int(d.devnum) == dev.DevNum {
			d.device_entry.device_flags &^= 0x00000002
			mtp := C.LIBMTP_Open_Raw_Device(d)
			if mtp == nil {
				return nil, fmt.Errorf("open failed")
			}
			return mtp, nil
		}
	}
	return nil, fmt.Errorf("device not found")
}

func Close(mtp *C.LIBMTP_mtpdevice_t) { C.LIBMTP_Release_Device(mtp) }

func DeviceInfo(mtp *C.LIBMTP_mtpdevice_t) map[string]string {
	info := map[string]string{}
	if v := C.LIBMTP_Get_Manufacturername(mtp); v != nil {
		info["manufacturer"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	if v := C.LIBMTP_Get_Modelname(mtp); v != nil {
		info["model"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	if v := C.LIBMTP_Get_Serialnumber(mtp); v != nil {
		info["serial"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	if v := C.LIBMTP_Get_Deviceversion(mtp); v != nil {
		info["version"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	if v := C.LIBMTP_Get_Friendlyname(mtp); v != nil {
		info["friendly"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	return info
}

func ListFiles(mtp *C.LIBMTP_mtpdevice_t) []string {
	var out []string
	fl := C.LIBMTP_Get_Filelisting(mtp)
	for f := fl; f != nil; f = f.next {
		name := ""
		if f.filename != nil {
			name = C.GoString(f.filename)
		}
		out = append(out, fmt.Sprintf("id=%d size=%d name=%s", uint32(f.item_id), uint64(f.filesize), name))
	}
	// free? LIBMTP_destroy_file_t per node? We'll leave; process exits.
	return out
}

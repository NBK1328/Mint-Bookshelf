package device

/*
#cgo CFLAGS: -I/opt/homebrew/include
#cgo LDFLAGS: -L/opt/homebrew/lib -lmtp -lusb-1.0
#include <stdlib.h>
#include <libmtp.h>
#include <libusb-1.0/libusb.h>

static void detachKernelDriver(int bus, int devnum) {
	libusb_context *ctx = NULL;
	libusb_init(&ctx);
	libusb_device **devs;
	ssize_t n = libusb_get_device_list(ctx, &devs);
	for (ssize_t i = 0; i < n; i++) {
		if (libusb_get_bus_number(devs[i]) == bus && libusb_get_device_address(devs[i]) == devnum) {
			libusb_device_handle *h;
			if (libusb_open(devs[i], &h) == LIBUSB_SUCCESS) {
				if (libusb_kernel_driver_active(h, 0)) {
					libusb_detach_kernel_driver(h, 0);
				}
				libusb_close(h);
			}
			break;
		}
	}
	libusb_free_device_list(devs, 1);
	libusb_exit(ctx);
}
*/
import "C"

import (
	"fmt"
	"os"
	"path/filepath"
	"unsafe"
)

type RawDevice struct {
	Bus       int    `json:"bus"`
	DevNum    int    `json:"devNum"`
	VendorID  uint16 `json:"vendorID"`
	ProductID uint16 `json:"productID"`
	Vendor    string `json:"vendor"`
	Product   string `json:"product"`
}

func Init() { C.LIBMTP_Init() }

func Detect() ([]RawDevice, error) {
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
	out := make([]RawDevice, 0, int(n))
	base := unsafe.Pointer(raw)
	sz := unsafe.Sizeof(*raw)
	for i := 0; i < int(n); i++ {
		d := (*C.LIBMTP_raw_device_t)(unsafe.Pointer(uintptr(base) + uintptr(i)*sz))
		dev := RawDevice{
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

type Session struct {
	ptr *C.LIBMTP_mtpdevice_t
}

func Open(dev RawDevice) (*Session, error) {
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
			mtp := C.LIBMTP_Open_Raw_Device(d)
			if mtp == nil {
				return nil, fmt.Errorf("open failed")
			}
			return &Session{ptr: mtp}, nil
		}
	}
	return nil, fmt.Errorf("device not found")
}

func (s *Session) Close() {
	if s.ptr != nil {
		C.LIBMTP_Release_Device(s.ptr)
		s.ptr = nil
	}
}

func (s *Session) Info() map[string]string {
	info := map[string]string{}
	if v := C.LIBMTP_Get_Manufacturername(s.ptr); v != nil {
		info["manufacturer"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	if v := C.LIBMTP_Get_Modelname(s.ptr); v != nil {
		info["model"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	if v := C.LIBMTP_Get_Serialnumber(s.ptr); v != nil {
		info["serial"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	if v := C.LIBMTP_Get_Deviceversion(s.ptr); v != nil {
		info["version"] = C.GoString(v)
		C.free(unsafe.Pointer(v))
	}
	return info
}

type FileEntry struct {
	ID        uint32 `json:"id"`
	ParentID  uint32 `json:"parentID"`
	StorageID uint32 `json:"storageID"`
	Name      string `json:"name"`
	Size      uint64 `json:"size"`
	Modified  int64  `json:"modified"`
	IsFolder  bool   `json:"isFolder"`
}

func (s *Session) ListFiles() ([]FileEntry, error) {
	storages := s.Storages()

	cached := s.ptr != nil && s.ptr.cached != 0

	var out []FileEntry
	seen := make(map[uint32]bool)

	var walk func(storageID, parentID uint32, depth int)
	walk = func(storageID, parentID uint32, depth int) {
		if depth > 64 {
			return
		}
		fl := C.LIBMTP_Get_Files_And_Folders(s.ptr, C.uint(storageID), C.uint(parentID))
		for f := fl; f != nil; f = f.next {
			id := uint32(f.item_id)
			if seen[id] {
				continue
			}
			seen[id] = true

			name := ""
			if f.filename != nil {
				name = C.GoString(f.filename)
			}
			isFolder := f.filetype == C.LIBMTP_FILETYPE_FOLDER
			parent := uint32(f.parent_id)
			if parent == uint32(C.LIBMTP_FILES_AND_FOLDERS_ROOT) {
				parent = 0
			}
			out = append(out, FileEntry{
				ID:        id,
				ParentID:  parent,
				StorageID: uint32(f.storage_id),
				Name:      name,
				Size:      uint64(f.filesize),
				Modified:  int64(f.modificationdate),
				IsFolder:  isFolder,
			})
			if isFolder {
				walk(storageID, id, depth+1)
			}
		}
		for f := fl; f != nil; {
			next := f.next
			C.LIBMTP_destroy_file_t(f)
			f = next
		}
	}

	if !cached {
		if len(storages) == 0 {
			walk(0, uint32(C.LIBMTP_FILES_AND_FOLDERS_ROOT), 0)
		} else {
			for _, st := range storages {
				walk(st.ID, uint32(C.LIBMTP_FILES_AND_FOLDERS_ROOT), 0)
			}
		}
	}

	// Some devices (including Kindle Scribe) are "cached" and refuse
	// LIBMTP_Get_Files_And_Folders. Fall back to the flat file listing,
	// which is known to work on those devices.
	if len(out) == 0 {
		fl := C.LIBMTP_Get_Filelisting(s.ptr)
		for f := fl; f != nil; f = f.next {
			id := uint32(f.item_id)
			if seen[id] {
				continue
			}
			seen[id] = true
			name := ""
			if f.filename != nil {
				name = C.GoString(f.filename)
			}
			parent := uint32(f.parent_id)
			if parent == uint32(C.LIBMTP_FILES_AND_FOLDERS_ROOT) {
				parent = 0
			}
			out = append(out, FileEntry{
				ID:        id,
				ParentID:  parent,
				StorageID: uint32(f.storage_id),
				Name:      name,
				Size:      uint64(f.filesize),
				Modified:  int64(f.modificationdate),
				IsFolder:  f.filetype == C.LIBMTP_FILETYPE_FOLDER,
			})
		}
		for f := fl; f != nil; {
			next := f.next
			C.LIBMTP_destroy_file_t(f)
			f = next
		}
	}

	// Cached devices return files only. Reconstruct the directory tree by
	// querying metadata for each unique parent_id (and its ancestors).
	hasFolders := false
	for _, f := range out {
		if f.IsFolder {
			hasFolders = true
			break
		}
	}
	if !hasFolders && len(out) > 0 {
		resolved := make(map[uint32]bool)
		var folders []FileEntry
		var resolve func(id, storageID uint32, depth int)
		resolve = func(id, storageID uint32, depth int) {
			if depth > 64 {
				return
			}
			for id != 0 && !resolved[id] {
				resolved[id] = true
				m := C.LIBMTP_Get_Filemetadata(s.ptr, C.uint(id))
				if m == nil {
					return
				}
				parent := uint32(m.parent_id)
				if parent == uint32(C.LIBMTP_FILES_AND_FOLDERS_ROOT) {
					parent = 0
				}
				name := ""
				if m.filename != nil {
					name = C.GoString(m.filename)
				}
				isFolder := m.filetype == C.LIBMTP_FILETYPE_FOLDER
				st := uint32(m.storage_id)
				if st == 0 {
					st = storageID
				}
				C.LIBMTP_destroy_file_t(m)
				if !isFolder {
					return
				}
				folders = append(folders, FileEntry{
					ID:        id,
					ParentID:  parent,
					StorageID: st,
					Name:      name,
					IsFolder:  true,
				})
				id = parent
				storageID = st
			}
		}
		for _, f := range out {
			resolve(f.ParentID, f.StorageID, 0)
		}
		for _, f := range folders {
			if !seen[f.ID] {
				seen[f.ID] = true
				out = append(out, f)
			}
		}
	}
	return out, nil
}

func (s *Session) storageOrDefault(storageID uint32) uint32 {
	if storageID != 0 {
		return storageID
	}
	if st := s.Storages(); len(st) > 0 {
		return st[0].ID
	}
	return 0
}

func (s *Session) Upload(localPath string, parentID uint32, storageID uint32, onProgress func(sent, total uint64)) error {
	storageID = s.storageOrDefault(storageID)
	fi, err := osStat(localPath)
	if err != nil {
		return err
	}
	ft := C.LIBMTP_new_file_t()
	defer C.LIBMTP_destroy_file_t(ft)
	name := filepathBase(localPath)
	cname := C.CString(name)
	ft.filename = cname
	ft.filesize = C.ulonglong(fi.Size())
	ft.parent_id = C.uint(parentID)
	ft.storage_id = C.uint(storageID)
	ft.filetype = C.LIBMTP_FILETYPE_UNKNOWN
	// progress callback
	_ = onProgress
	cpath := C.CString(localPath)
	defer C.free(unsafe.Pointer(cpath))
	ret := C.LIBMTP_Send_File_From_File(s.ptr, cpath, ft, nil, nil)
	if ret != 0 {
		return fmt.Errorf("upload failed: %d", int(ret))
	}
	return nil
}

func (s *Session) Delete(objectID uint32) error {
	ret := C.LIBMTP_Delete_Object(s.ptr, C.uint(objectID))
	if ret != 0 {
		return fmt.Errorf("delete failed: %d", int(ret))
	}
	return nil
}

func osStat(p string) (os.FileInfo, error) { return os.Stat(p) }
func filepathBase(p string) string         { return filepath.Base(p) }

type Storage struct {
	ID          uint32
	Total       uint64
	Free        uint64
	Description string
}

func (s *Session) Storages() []Storage {
	var out []Storage
	ret := C.LIBMTP_Get_Storage(s.ptr, C.LIBMTP_STORAGE_SORTBY_NOTSORTED)
	if ret != 0 {
		// ignore; storage list populated in struct
	}
	st := s.ptr.storage
	for st != nil {
		out = append(out, Storage{
			ID:    uint32(st.id),
			Total: uint64(st.MaxCapacity),
			Free:  uint64(st.FreeSpaceInBytes),
		})
		st = st.next
	}
	return out
}

func IsConnected() bool {
	devs, err := Detect()
	if err != nil {
		return false
	}
	for _, d := range devs {
		if d.VendorID == 0x1949 {
			return true
		}
	}
	return len(devs) > 0
}

func (s *Session) Download(objectID uint32, localPath string, onProgress func(sent, total uint64)) error {
	cpath := C.CString(localPath)
	defer C.free(unsafe.Pointer(cpath))
	ret := C.LIBMTP_Get_File_To_File(s.ptr, C.uint(objectID), cpath, nil, nil)
	if ret != 0 {
		return fmt.Errorf("download failed: %d", int(ret))
	}
	_ = onProgress
	return nil
}

func (s *Session) Move(objectID, storageID, parentID uint32) error {
	storageID = s.storageOrDefault(storageID)
	ret := C.LIBMTP_Move_Object(s.ptr, C.uint(objectID), C.uint(storageID), C.uint(parentID))
	if ret != 0 {
		return fmt.Errorf("move failed: %d", int(ret))
	}
	return nil
}

func (s *Session) Copy(objectID, storageID, parentID uint32) error {
	storageID = s.storageOrDefault(storageID)
	ret := C.LIBMTP_Copy_Object(s.ptr, C.uint(objectID), C.uint(storageID), C.uint(parentID))
	if ret != 0 {
		return fmt.Errorf("copy failed: %d", int(ret))
	}
	return nil
}

func (s *Session) CreateFolder(name string, parentID, storageID uint32) (uint32, error) {
	storageID = s.storageOrDefault(storageID)
	cname := C.CString(name)
	defer C.free(unsafe.Pointer(cname))
	id := C.LIBMTP_Create_Folder(s.ptr, cname, C.uint(parentID), C.uint(storageID))
	if id == 0 {
		return 0, fmt.Errorf("create folder failed")
	}
	return uint32(id), nil
}

func (s *Session) Rename(objectID uint32, newName string) error {
	cname := C.CString(newName)
	defer C.free(unsafe.Pointer(cname))
	ret := C.LIBMTP_Set_Object_Filename(s.ptr, C.uint(objectID), cname)
	if ret != 0 {
		return fmt.Errorf("rename failed: %d", int(ret))
	}
	return nil
}

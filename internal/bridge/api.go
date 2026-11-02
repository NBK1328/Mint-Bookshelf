package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
	"unsafe"

	"github.com/kindle-manager/kindle-manager/internal/converter"
	"github.com/kindle-manager/kindle-manager/internal/device"
	"github.com/kindle-manager/kindle-manager/internal/filesystem"
	"github.com/kindle-manager/kindle-manager/internal/library"
	"github.com/kindle-manager/kindle-manager/internal/operations"
	"github.com/kindle-manager/kindle-manager/internal/storage"
)

type appState struct {
	db     *storage.DB
	lib    *library.Scanner
	conv   *converter.Calibre
	ops    *operations.Manager
	dbPath string
}

var state *appState
var logger *slog.Logger
var logFile *os.File
var currentDevice *device.Session
var currentBus, currentDev int
var deviceMu sync.Mutex

//export KM_Initialize
func KM_Initialize(dbPath *C.char) *C.char {
	if state != nil {
		shutdown()
	}
	p := C.GoString(dbPath)
	home, _ := os.UserHomeDir()
	logDir := filepath.Join(home, "Library", "Logs", "KindleManager")
	os.MkdirAll(logDir, 0o755)
	f, _ := os.OpenFile(filepath.Join(logDir, "core.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if f != nil {
		logFile = f
		logger = slog.New(slog.NewTextHandler(f, nil))
		slog.SetDefault(logger)
	}
	if p == "" {
		d, _ := os.UserHomeDir()
		p = filepath.Join(d, "Library", "Application Support", "KindleManager", "library.db")
	}
	db, err := storage.Open(p)
	if err != nil {
		shutdown()
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	cal, _ := converter.DetectCalibre()
	st := &appState{db: db, lib: library.NewScanner(db), conv: cal, ops: operations.NewManager(2, db), dbPath: p}
	device.Init()
	state = st
	return C.CString(mustJSON(map[string]any{"ok": true, "db": p, "calibre": cal != nil}))
}

//export KM_Shutdown
func KM_Shutdown() {
	shutdown()
}

func shutdown() {
	allDone := true
	if state != nil {
		if state.ops != nil {
			allDone = state.ops.Shutdown(5 * time.Second)
		}
	}
	if !allDone && logger != nil {
		logger.Warn("shutdown timed out waiting for operations")
	}
	deviceMu.Lock()
	if currentDevice != nil {
		currentDevice.Close()
		currentDevice = nil
	}
	currentBus, currentDev = 0, 0
	deviceMu.Unlock()
	if state != nil {
		if state.db != nil && allDone {
			state.db.Close()
		}
		state = nil
	}
	if logFile != nil {
		logFile.Close()
		logFile = nil
	}
	logger = nil
}

//export KM_GetVersion
func KM_GetVersion() *C.char {
	return C.CString("0.1.0")
}

//export KM_LibraryScan
func KM_LibraryScan(root *C.char) *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	result, err := state.lib.ScanRoot(C.GoString(root))
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(dataJSON(result))
}

//export KM_LibraryGetBooks
func KM_LibraryGetBooks() *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	books, err := state.db.Books()
	if books == nil {
		books = []storage.Book{}
	}
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(dataJSON(books))
}

//export KM_DeviceDiscover
func KM_DeviceDiscover() *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	device.Init()
	devs, err := device.Detect()
	if devs == nil {
		devs = []device.RawDevice{}
	}
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(dataJSON(devs))
}

//export KM_FreeMemory
func KM_FreeMemory(p unsafe.Pointer) {
	C.free(p)
}

//export KM_DeviceGetList
func KM_DeviceGetList() *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	device.Init()
	devs, err := device.Detect()
	if devs == nil {
		devs = []device.RawDevice{}
	}
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(dataJSON(devs))
}

//export KM_DeviceGetInfo
func KM_DeviceGetInfo(bus, dev int) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	device.Init()
	if currentDevice != nil && currentBus == bus && currentDev == dev {
		info := currentDevice.Info()
		if len(info) > 0 {
			return C.CString(dataJSON(map[string]any{
				"info":     info,
				"storages": currentDevice.Storages(),
			}))
		}
		currentDevice.Close()
		currentDevice = nil
	}
	if currentDevice != nil {
		currentDevice.Close()
		currentDevice = nil
	}
	devs, err := device.Detect()
	if err != nil {
		if logger != nil {
			logger.Error("device detect failed", "err", err)
		}
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	for _, d := range devs {
		if d.Bus == bus && d.DevNum == dev {
			sess, err := device.Open(d)
			if err != nil {
				if logger != nil {
					logger.Error("device open failed", "bus", bus, "dev", dev, "err", err)
				}
				return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
			}
			currentDevice = sess
			currentBus, currentDev = bus, dev
			info := sess.Info()
			if logger != nil {
				logger.Info("device opened", "bus", bus, "dev", dev, "info", info)
			}
			return C.CString(dataJSON(map[string]any{
				"info":     info,
				"storages": sess.Storages(),
			}))
		}
	}
	if logger != nil {
		logger.Warn("device not found", "bus", bus, "dev", dev, "detected", len(devs))
	}
	return C.CString(mustJSON(map[string]any{"ok": false, "error": "device not found"}))
}

//export KM_DeviceListBooks
func KM_DeviceListBooks() *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	files, err := currentDevice.ListFiles()
	if files == nil {
		files = []device.FileEntry{}
	}
	if logger != nil {
		if err != nil {
			logger.Error("device list failed", "err", err)
		} else {
			folders := 0
			for _, f := range files {
				if f.IsFolder {
					folders++
				}
			}
			logger.Info("device listed", "count", len(files), "folders", folders)
		}
	}
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(dataJSON(files))
}

//export KM_DeviceUploadBook
func KM_DeviceUploadBook(localPath *C.char, parentID, storageID uint32) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	path := C.GoString(localPath)
	if logger != nil {
		logger.Info("device upload", "path", path, "parent", parentID, "storage", storageID)
	}
	err := currentDevice.Upload(path, parentID, storageID, nil)
	if err != nil {
		if logger != nil {
			logger.Error("device upload failed", "path", path, "err", err)
		}
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true}))
}

//export KM_DeviceDeleteBook
func KM_DeviceDeleteBook(objectID uint32) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	if logger != nil {
		logger.Info("device delete", "id", objectID)
	}
	err := currentDevice.Delete(objectID)
	if err != nil {
		if logger != nil {
			logger.Error("device delete failed", "id", objectID, "err", err)
		}
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true}))
}

//export KM_LibraryUpdateMetadata
func KM_LibraryUpdateMetadata(id int64, title, author *C.char) *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	books, _ := state.db.Books()
	for _, b := range books {
		if b.ID == id {
			b.Title = C.GoString(title)
			b.Author = C.GoString(author)
			if err := state.db.UpsertBook(&b); err != nil {
				return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
			}
			return C.CString(mustJSON(map[string]any{"ok": true}))
		}
	}
	return C.CString(mustJSON(map[string]any{"ok": false, "error": "not found"}))
}

//export KM_LibraryDeleteBook
func KM_LibraryDeleteBook(id int64) *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	books, _ := state.db.Books()
	for _, b := range books {
		if b.ID == id {
			if err := state.db.DeleteBookPath(b.Path); err != nil {
				return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
			}
			return C.CString(mustJSON(map[string]any{"ok": true}))
		}
	}
	return C.CString(mustJSON(map[string]any{"ok": false, "error": "not found"}))
}

//export KM_ConvertBook
func KM_ConvertBook(input, output, format *C.char) *C.char {
	if state == nil || state.conv == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no calibre"}))
	}
	in := C.GoString(input)
	out := C.GoString(output)
	formatStr := C.GoString(format)
	if out == "" {
		out = ""
	}
	id, err := state.ops.Submit("convert", in, func(ctx context.Context, t *operations.Task) error {
		return state.conv.Convert(ctx, converter.Options{Input: in, Output: out, ToFormat: formatStr}, func(line string) {
			// parse percentage like "34% ..."
			for i := 0; i+1 < len(line); i++ {
				if line[i] >= '0' && line[i] <= '9' {
					j := i
					for j < len(line) && line[j] >= '0' && line[j] <= '9' {
						j++
					}
					if j < len(line) && line[j] == '%' {
						var p int
						fmt.Sscanf(line[i:j], "%d", &p)
						t.SetProgress(float64(p) / 100.0)
						return
					}
					i = j
				}
			}
		})
	})
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true, "operation": id}))
}

//export KM_OperationGetStatus
func KM_OperationGetStatus(id *C.char) *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	snapshot, ok := state.ops.Get(C.GoString(id))
	if ok {
		return C.CString(dataJSON(snapshot))
	}
	if state.db != nil {
		if op, err := state.db.GetOperation(C.GoString(id)); err == nil {
			return C.CString(dataJSON(op))
		}
	}
	return C.CString(mustJSON(map[string]any{"ok": false, "error": "not found"}))
}

//export KM_OperationCancel
func KM_OperationCancel(id *C.char) *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	ok := state.ops.Cancel(C.GoString(id))
	return C.CString(mustJSON(map[string]any{"ok": ok}))
}

//export KM_FilesystemList
func KM_FilesystemList(path *C.char) *C.char {
	entries, err := filesystem.ListDir(C.GoString(path))
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	if entries == nil {
		entries = []filesystem.Entry{}
	}
	return C.CString(dataJSON(entries))
}

//export KM_SettingGet
func KM_SettingGet(key *C.char) *C.char {
	if state == nil {
		return C.CString("")
	}
	v, _ := state.db.GetSetting(C.GoString(key))
	return C.CString(v)
}

//export KM_SettingSet
func KM_SettingSet(key, value *C.char) *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	if err := state.db.SetSetting(C.GoString(key), C.GoString(value)); err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true}))
}

//export KM_LibraryGetBook
func KM_LibraryGetBook(id int64) *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	books, _ := state.db.Books()
	for _, b := range books {
		if b.ID == id {
			return C.CString(dataJSON(b))
		}
	}
	return C.CString(mustJSON(map[string]any{"ok": false, "error": "not found"}))
}

//export KM_DeviceIsConnected
func KM_DeviceIsConnected() C.int {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if device.IsConnected() {
		return 1
	}
	return 0
}

func operationList() ([]storage.Operation, error) {
	byID := map[string]storage.Operation{}
	if state.db != nil {
		ops, err := state.db.ListOperations()
		if err != nil {
			return nil, err
		}
		for _, op := range ops {
			byID[op.ID] = op
		}
	}
	if state.ops != nil {
		for _, task := range state.ops.List() {
			byID[task.ID] = storage.Operation{
				ID:        task.ID,
				Type:      task.Type,
				Status:    string(task.Status),
				Title:     task.Title,
				Progress:  task.Progress,
				StartedAt: task.StartedAt,
				EndedAt:   task.EndedAt,
				Error:     task.Error,
			}
		}
	}
	out := make([]storage.Operation, 0, len(byID))
	for _, op := range byID {
		out = append(out, op)
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i].StartedAt, out[j].StartedAt
		if a == nil {
			return false
		}
		if b == nil {
			return true
		}
		return a.After(*b)
	})
	return out, nil
}

//export KM_OperationList
func KM_OperationList() *C.char {
	if state == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "not initialized"}))
	}
	ops, err := operationList()
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(dataJSON(ops))
}

//export KM_DeviceMoveBook
func KM_DeviceMoveBook(objectID, storageID, parentID uint32) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	if logger != nil {
		logger.Info("device move", "id", objectID, "storage", storageID, "parent", parentID)
	}
	if err := currentDevice.Move(objectID, storageID, parentID); err != nil {
		if logger != nil {
			logger.Error("device move failed", "id", objectID, "err", err)
		}
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true}))
}

//export KM_DeviceCopyBook
func KM_DeviceCopyBook(objectID, storageID, parentID uint32) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	if logger != nil {
		logger.Info("device copy", "id", objectID, "storage", storageID, "parent", parentID)
	}
	if err := currentDevice.Copy(objectID, storageID, parentID); err != nil {
		if logger != nil {
			logger.Error("device copy failed", "id", objectID, "err", err)
		}
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true}))
}

//export KM_DeviceCreateFolder
func KM_DeviceCreateFolder(name *C.char, parentID, storageID uint32) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	id, err := currentDevice.CreateFolder(C.GoString(name), parentID, storageID)
	if err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true, "id": id}))
}

//export KM_DeviceRenameBook
func KM_DeviceRenameBook(objectID uint32, newName *C.char) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	if err := currentDevice.Rename(objectID, C.GoString(newName)); err != nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true}))
}

//export KM_DeviceDownloadBook
func KM_DeviceDownloadBook(objectID uint32, localPath *C.char) *C.char {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	if currentDevice == nil {
		return C.CString(mustJSON(map[string]any{"ok": false, "error": "no device"}))
	}
	path := C.GoString(localPath)
	if logger != nil {
		logger.Info("device download", "id", objectID, "path", path)
	}
	err := currentDevice.Download(objectID, path, nil)
	if err != nil {
		if logger != nil {
			logger.Error("device download failed", "id", objectID, "path", path, "err", err)
		}
		return C.CString(mustJSON(map[string]any{"ok": false, "error": err.Error()}))
	}
	return C.CString(mustJSON(map[string]any{"ok": true}))
}

func main() {}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

func dataJSON(v any) string {
	b, _ := json.Marshal(map[string]any{"ok": true, "data": v})
	return string(b)
}

//go:build mtp

package device

import (
	"testing"
)

func TestDetect(t *testing.T) {
	Init()
	devs, err := Detect()
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("devices: %d", len(devs))
	if len(devs) == 0 {
		t.Skip("no device connected")
	}
	// try open first
	s, err := Open(devs[0])
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	files, err := s.ListFiles()
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("files: %d", len(files))
	sts := s.Storages()
	t.Logf("storages: %+v", sts)
}

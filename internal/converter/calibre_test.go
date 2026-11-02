package converter

import (
	"context"
	"testing"
)

func TestDetectCalibre(t *testing.T) {
	c, err := DetectCalibre()
	if err != nil {
		t.Skip("calibre not installed:", err)
	}
	t.Logf("path=%s version=%s", c.Path, c.Version)
	if c.Version == "" {
		v, err := c.VersionString(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		t.Log("version", v)
	}
	if !c.ArchOK() {
		t.Log("warning: arm64 not detected in file output")
	}
}

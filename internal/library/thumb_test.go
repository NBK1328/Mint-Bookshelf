package library

import (
	"os"
	"testing"
)

func TestThumbnail(t *testing.T) {
	if _, err := os.Stat("/tmp/cover.png"); err != nil {
		t.Skip("cover missing")
	}
	p, err := Thumbnail("/tmp/cover.png", 64)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(p); err != nil {
		t.Fatal(err)
	}
	t.Log(p)
}

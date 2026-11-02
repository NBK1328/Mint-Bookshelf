package converter

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestConvertStreamsProgressLines(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "ebook-convert")
	body := "#!/bin/sh\nprintf '10%%\\n'\nprintf '50%%\\n' >&2\nprintf '100%%\\n'\n"
	if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}

	c := &Calibre{Path: script}
	var mu sync.Mutex
	var lines []string
	err := c.Convert(context.Background(), Options{
		Input:    filepath.Join(dir, "in.epub"),
		Output:   filepath.Join(dir, "out.azw3"),
		ToFormat: "azw3",
	}, func(line string) {
		mu.Lock()
		lines = append(lines, line)
		mu.Unlock()
	})
	if err != nil {
		t.Fatal(err)
	}

	mu.Lock()
	defer mu.Unlock()
	if len(lines) != 3 {
		t.Fatalf("lines = %v, want 3 lines", lines)
	}
	seen := map[string]bool{}
	for _, line := range lines {
		seen[line] = true
	}
	for _, want := range []string{"10%", "50%", "100%"} {
		if !seen[want] {
			t.Fatalf("missing %q in %v", want, lines)
		}
	}
}

func TestConvertReportsStartFailure(t *testing.T) {
	c := &Calibre{Path: filepath.Join(t.TempDir(), "missing-ebook-convert")}
	if err := c.Convert(context.Background(), Options{Input: "in", Output: "out", ToFormat: "azw3"}, nil); err == nil {
		t.Fatal("expected start failure")
	}
}

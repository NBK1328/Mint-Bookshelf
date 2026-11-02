package library

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func CacheDir() string {
	home, _ := os.UserHomeDir()
	d := filepath.Join(home, "Library", "Caches", "KindleManager", "covers")
	os.MkdirAll(d, 0o755)
	return d
}

func ExtractCovers(b *storage.Book) {
	if !strings.HasPrefix(b.CoverPath, "zip://") {
		return
	}
	// format: zip:///path/to/book.epub!/OPS/cover.jpg
	parts := strings.SplitN(b.CoverPath, "!", 2)
	if len(parts) != 2 {
		return
	}
	zipPath := strings.TrimPrefix(parts[0], "zip://")
	entry := parts[1]
	ext := filepath.Ext(entry)
	if ext == "" {
		ext = ".jpg"
	}
	dest := filepath.Join(CacheDir(), sanitize(b.Path)+ext)
	if _, err := os.Stat(dest); err == nil {
		b.CoverPath = dest
		return
	}
	if err := ExtractCoverZip(zipPath, entry, dest); err != nil {
		b.CoverPath = ""
		return
	}
	b.CoverPath = dest
}

func sanitize(p string) string {
	r := strings.NewReplacer("/", "_", "\\", "_", " ", "_")
	return r.Replace(filepath.Base(p))
}


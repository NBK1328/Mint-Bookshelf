package library

import (
	"crypto/sha1"
	"encoding/hex"
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
	dest := filepath.Join(CacheDir(), cacheKey(b.Path)+ext)
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

func cacheKey(p string) string {
	sum := sha1.Sum([]byte(p))
	return hex.EncodeToString(sum[:])
}

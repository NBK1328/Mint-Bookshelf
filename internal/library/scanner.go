package library

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"io/fs"
	"log/slog"
	"path/filepath"
	"strings"
	"time"

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

var bookExts = map[string]bool{
	".epub": true, ".fb2": true, ".mobi": true, ".azw": true, ".azw3": true,
	".pdf": true, ".txt": true, ".html": true, ".htm": true, ".docx": true, ".rtf": true,
}

type Scanner struct {
	DB *storage.DB
}

func NewScanner(db *storage.DB) *Scanner { return &Scanner{DB: db} }

func (s *Scanner) ScanRoot(root string) (int, error) {
	resolved, err := filepath.EvalSymlinks(root)
	if err != nil {
		resolved = root
	}
	root = resolved
	if err := s.DB.AddRoot(root); err != nil {
		return 0, err
	}
	added := 0
	slog.Info("scan start", "root", root)
	err = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if !bookExts[ext] {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		b := &storage.Book{
			Path:       path,
			Format:     strings.TrimPrefix(ext, "."),
			Size:       info.Size(),
			ModifiedAt: info.ModTime(),
			AddedAt:    time.Now(),
		}
		b.Title = strings.TrimSuffix(filepath.Base(path), ext)
		b.Fingerprint = fingerprint(path, info.Size(), info.ModTime())
		// metadata
		fillMetadata(b)
	ExtractCovers(b)
		if err := s.DB.UpsertBook(b); err != nil {
			return err
		}
		added++
		return nil
	})
	slog.Info("scan done", "root", root, "added", added, "err", err)
	return added, err
}

func fingerprint(path string, size int64, mt time.Time) string {
	h := sha1.New()
	fmt.Fprintf(h, "%s|%d|%d", path, size, mt.Unix())
	return hex.EncodeToString(h.Sum(nil))
}

func fillMetadata(b *storage.Book) {
	switch b.Format {
	case "epub":
		readEPUBMetadata(b)
	case "fb2":
		readFB2Metadata(b)
	}
}

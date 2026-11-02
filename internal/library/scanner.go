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

type ScanResult struct {
	Scanned int `json:"scanned"`
	Added   int `json:"added"`
	Updated int `json:"updated"`
	Deleted int `json:"deleted"`
}

func (s *Scanner) ScanRoot(root string) (ScanResult, error) {
	var result ScanResult

	resolved, err := filepath.EvalSymlinks(root)
	if err != nil {
		resolved = root
	}
	root = filepath.Clean(resolved)
	if err := s.DB.AddRoot(root); err != nil {
		return result, err
	}

	existing, err := s.DB.Books()
	if err != nil {
		return result, err
	}
	byPath := make(map[string]storage.Book, len(existing))
	for _, book := range existing {
		byPath[book.Path] = book
	}

	seen := make(map[string]bool)
	slog.Info("scan start", "root", root)
	walkErr := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
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

		path = filepath.Clean(path)
		seen[path] = true
		info, err := d.Info()
		if err != nil {
			return nil
		}
		result.Scanned++

		b := &storage.Book{
			Path:       path,
			Format:     strings.TrimPrefix(ext, "."),
			Size:       info.Size(),
			ModifiedAt: info.ModTime(),
			AddedAt:    time.Now(),
		}
		b.Title = strings.TrimSuffix(filepath.Base(path), ext)
		b.Fingerprint = fingerprint(path, info.Size(), info.ModTime())
		fillMetadata(b)
		ExtractCovers(b)
		if err := s.DB.UpsertBook(b); err != nil {
			return err
		}
		if _, ok := byPath[path]; ok {
			result.Updated++
		} else {
			result.Added++
		}
		return nil
	})
	if walkErr != nil {
		return result, walkErr
	}

	for _, book := range existing {
		if !isUnderRoot(book.Path, root) {
			continue
		}
		if seen[filepath.Clean(book.Path)] {
			continue
		}
		if err := s.DB.DeleteBookPath(book.Path); err != nil {
			return result, err
		}
		result.Deleted++
	}

	slog.Info("scan done", "root", root, "scanned", result.Scanned, "added", result.Added, "updated", result.Updated, "deleted", result.Deleted)
	return result, nil
}

func isUnderRoot(path, root string) bool {
	path = filepath.Clean(path)
	root = filepath.Clean(root)
	if path == root {
		return false
	}
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
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

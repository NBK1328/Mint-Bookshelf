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
	Moved   int `json:"moved"`
	Deleted int `json:"deleted"`
}

type scanCandidate struct {
	path     string
	ext      string
	size     int64
	modified time.Time
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
	var files []scanCandidate
	slog.Info("scan start", "root", root)
	walkErr := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
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
		path = filepath.Clean(path)
		seen[path] = true
		result.Scanned++
		files = append(files, scanCandidate{
			path:     path,
			ext:      ext,
			size:     info.Size(),
			modified: info.ModTime(),
		})
		return nil
	})
	if walkErr != nil {
		return result, walkErr
	}

	unseenByFingerprint := make(map[string][]storage.Book)
	for _, book := range existing {
		if !isUnderRoot(book.Path, root) || seen[filepath.Clean(book.Path)] {
			continue
		}
		if book.Fingerprint == "" {
			continue
		}
		unseenByFingerprint[book.Fingerprint] = append(unseenByFingerprint[book.Fingerprint], book)
	}
	moved := make(map[int64]bool)

	for _, file := range files {
		b := &storage.Book{
			Path:        file.path,
			Format:      strings.TrimPrefix(file.ext, "."),
			Size:        file.size,
			ModifiedAt:  file.modified,
			AddedAt:     time.Now(),
			Fingerprint: fingerprint(file.size, file.modified),
		}
		b.Title = strings.TrimSuffix(filepath.Base(file.path), file.ext)
		fillMetadata(b)
		ExtractCovers(b)

		if previous, ok := byPath[file.path]; ok {
			b.AddedAt = previous.AddedAt
			if err := s.DB.UpsertBook(b); err != nil {
				return result, err
			}
			result.Updated++
			continue
		}

		if candidates := unseenByFingerprint[b.Fingerprint]; len(candidates) > 0 {
			previous := candidates[0]
			unseenByFingerprint[b.Fingerprint] = candidates[1:]
			if err := s.DB.MoveBookPath(previous.ID, file.path); err != nil {
				return result, err
			}
			b.AddedAt = previous.AddedAt
			if err := s.DB.UpsertBook(b); err != nil {
				return result, err
			}
			moved[previous.ID] = true
			result.Moved++
			continue
		}

		if err := s.DB.UpsertBook(b); err != nil {
			return result, err
		}
		result.Added++
	}

	for _, book := range existing {
		if !isUnderRoot(book.Path, root) || seen[filepath.Clean(book.Path)] || moved[book.ID] {
			continue
		}
		if err := s.DB.DeleteBookPath(book.Path); err != nil {
			return result, err
		}
		result.Deleted++
	}

	slog.Info("scan done", "root", root, "scanned", result.Scanned, "added", result.Added,
		"updated", result.Updated, "moved", result.Moved, "deleted", result.Deleted)
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

func fingerprint(size int64, mt time.Time) string {
	h := sha1.New()
	fmt.Fprintf(h, "%d|%d", size, mt.UnixNano())
	return hex.EncodeToString(h.Sum(nil))
}

func fillMetadata(b *storage.Book) {
	switch b.Format {
	case "epub":
		readEPUBMetadata(b)
	case "fb2":
		readFB2Metadata(b)
	default:
		readCalibreMetadata(b)
	}
}

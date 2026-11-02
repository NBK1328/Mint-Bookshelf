package library

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func TestCoverExtraction(t *testing.T) {
	if _, err := os.Stat("/tmp/coverbook.epub"); err != nil {
		t.Skip("cover epub missing")
	}
	dir, _ := os.MkdirTemp("", "cover")
	defer os.RemoveAll(dir)
	os.WriteFile(filepath.Join(dir, "c.epub"), mustRead("/tmp/coverbook.epub"), 0o644)

	dbf, _ := os.CreateTemp("", "km-*.db")
	dbf.Close()
	os.Remove(dbf.Name())
	db, _ := storage.Open(dbf.Name())
	defer db.Close()
	defer os.Remove(dbf.Name())

	sc := NewScanner(db)
	if _, err := sc.ScanRoot(dir); err != nil {
		t.Fatal(err)
	}
	books, _ := db.Books()
	if len(books) != 1 {
		t.Fatalf("books %d", len(books))
	}
	t.Logf("cover=%s", books[0].CoverPath)
	if books[0].CoverPath == "" {
		t.Fatal("cover not extracted")
	}
	if _, err := os.Stat(books[0].CoverPath); err != nil {
		t.Fatal(err)
	}
}

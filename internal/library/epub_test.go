package library

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func TestEPUBMetadata(t *testing.T) {
	if _, err := os.Stat("/tmp/testmeta.epub"); err != nil {
		t.Skip("test epub missing")
	}
	dir, _ := os.MkdirTemp("", "epub")
	defer os.RemoveAll(dir)
	os.WriteFile(filepath.Join(dir, "x.epub"), mustRead("/tmp/testmeta.epub"), 0o644)

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
	if books[0].Title != "Test Title" {
		t.Errorf("title=%q", books[0].Title)
	}
	if books[0].Author != "Test Author" {
		t.Errorf("author=%q", books[0].Author)
	}
	t.Logf("cover=%s", books[0].CoverPath)
}

func mustRead(p string) []byte {
	b, err := os.ReadFile(p)
	if err != nil {
		panic(err)
	}
	return b
}

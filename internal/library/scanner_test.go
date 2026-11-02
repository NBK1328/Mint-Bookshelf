package library

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func TestScan(t *testing.T) {
	dir, _ := os.MkdirTemp("", "lib")
	defer os.RemoveAll(dir)
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("hi"), 0o644)
	os.WriteFile(filepath.Join(dir, "b.pdf"), []byte("pdf"), 0o644)
	os.WriteFile(filepath.Join(dir, "ignore.png"), []byte("x"), 0o644)

	dbf, _ := os.CreateTemp("", "km-*.db")
	dbf.Close()
	os.Remove(dbf.Name())
	db, _ := storage.Open(dbf.Name())
	defer db.Close()
	defer os.Remove(dbf.Name())

	sc := NewScanner(db)
	n, err := sc.ScanRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Fatalf("expected 2, got %d", n)
	}
	books, _ := db.Books()
	if len(books) != 2 {
		t.Fatalf("books %d", len(books))
	}
	// rescan idempotent
	n2, _ := sc.ScanRoot(dir)
	if n2 != 2 {
		t.Fatalf("rescan added %d", n2)
	}
	books2, _ := db.Books()
	if len(books2) != 2 {
		t.Fatalf("dup books %d", len(books2))
	}
}

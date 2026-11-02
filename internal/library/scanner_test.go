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
	result, err := sc.ScanRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	if result.Scanned != 2 || result.Added != 2 {
		t.Fatalf("expected scanned=2 added=2, got %+v", result)
	}
	books, _ := db.Books()
	if len(books) != 2 {
		t.Fatalf("books %d", len(books))
	}
	// rescan idempotent
	result2, _ := sc.ScanRoot(dir)
	if result2.Added != 0 || result2.Updated != 2 {
		t.Fatalf("rescan result %+v", result2)
	}
	books2, _ := db.Books()
	if len(books2) != 2 {
		t.Fatalf("dup books %d", len(books2))
	}

	os.Remove(filepath.Join(dir, "a.txt"))
	result3, _ := sc.ScanRoot(dir)
	if result3.Deleted != 1 {
		t.Fatalf("delete result %+v", result3)
	}
	books3, _ := db.Books()
	if len(books3) != 1 {
		t.Fatalf("books after delete %d", len(books3))
	}
}

func TestScanAbortsWithoutDeletingOnWalkError(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("permission test does not work as root")
	}
	dir := t.TempDir()
	locked := filepath.Join(dir, "locked")
	if err := os.Mkdir(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(locked, "b.pdf"), []byte("pdf"), 0o644); err != nil {
		t.Fatal(err)
	}

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

	if err := os.Chmod(locked, 0o000); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(locked, 0o755)

	if _, err := sc.ScanRoot(dir); err == nil {
		t.Fatal("expected walk error")
	}
	books, _ := db.Books()
	if len(books) != 1 {
		t.Fatalf("books after failed scan = %d, want 1", len(books))
	}
}

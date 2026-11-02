package storage

import (
	"os"
	"testing"
	"time"
)

func TestSQLiteRoundTrip(t *testing.T) {
	f, _ := os.CreateTemp("", "km-*.db")
	f.Close()
	os.Remove(f.Name())
	db, err := Open(f.Name())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	defer os.Remove(f.Name())
	if err := db.AddRoot("/tmp/books"); err != nil {
		t.Fatal(err)
	}
	roots, _ := db.Roots()
	if len(roots) != 1 {
		t.Fatalf("roots: %v", roots)
	}
	b := &Book{Title: "T", Author: "A", Path: "/tmp/books/x.epub", Format: "epub", Size: 10, AddedAt: time.Now(), ModifiedAt: time.Now()}
	if err := db.UpsertBook(b); err != nil {
		t.Fatal(err)
	}
	got, _ := db.Books()
	if len(got) != 1 || got[0].Title != "T" {
		t.Fatalf("books: %+v", got)
	}
	res, _ := db.Search("t")
	if len(res) != 1 {
		t.Fatalf("search: %d", len(res))
	}
	// upsert idempotency
	if err := db.UpsertBook(b); err != nil {
		t.Fatal(err)
	}
	got2, _ := db.Books()
	if len(got2) != 1 {
		t.Fatalf("dup: %d", len(got2))
	}
}

func TestSearchUnicode(t *testing.T) {
	f, _ := os.CreateTemp("", "km-unicode-*.db")
	f.Close()
	os.Remove(f.Name())
	db, err := Open(f.Name())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	defer os.Remove(f.Name())

	book := &Book{Title: "Книга", Author: "Иван", Series: "Серия", Path: "/tmp/kniga.epub", Format: "epub"}
	if err := db.UpsertBook(book); err != nil {
		t.Fatal(err)
	}
	for _, query := range []string{"книга", "КНИГА", "иван", "серия"} {
		got, err := db.Search(query)
		if err != nil {
			t.Fatal(err)
		}
		if len(got) != 1 {
			t.Fatalf("query %q returned %d books", query, len(got))
		}
	}
}

func TestDeviceFoldersRoundTrip(t *testing.T) {
	f, _ := os.CreateTemp("", "km-folders-*.db")
	f.Close()
	os.Remove(f.Name())
	db, err := Open(f.Name())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	defer os.Remove(f.Name())

	folders := []DeviceFolder{
		{StorageID: 7, ObjectID: 1, ParentID: 0, Name: "A"},
		{StorageID: 7, ObjectID: 2, ParentID: 1, Name: "B"},
	}
	if err := db.ReplaceDeviceFolders("serial", folders); err != nil {
		t.Fatal(err)
	}
	got, err := db.DeviceFolders("serial")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("folders = %+v", got)
	}
	if err := db.ReplaceDeviceFolders("serial", folders[:1]); err != nil {
		t.Fatal(err)
	}
	got, _ = db.DeviceFolders("serial")
	if len(got) != 1 || got[0].Name != "A" {
		t.Fatalf("folders after replace = %+v", got)
	}
}

func TestOpenRemovesRelativePaths(t *testing.T) {
	f, _ := os.CreateTemp("", "km-relative-*.db")
	f.Close()
	os.Remove(f.Name())
	db, err := Open(f.Name())
	if err != nil {
		t.Fatal(err)
	}
	if err := db.UpsertBook(&Book{Path: "Applications/example.rtf"}); err != nil {
		t.Fatal(err)
	}
	if err := db.AddRoot("."); err != nil {
		t.Fatal(err)
	}
	db.Close()

	db, err = Open(f.Name())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	defer os.Remove(f.Name())
	books, _ := db.Books()
	if len(books) != 0 {
		t.Fatalf("relative paths were not removed: %+v", books)
	}
	roots, _ := db.Roots()
	if len(roots) != 0 {
		t.Fatalf("relative roots were not removed: %+v", roots)
	}
}

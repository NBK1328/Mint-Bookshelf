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

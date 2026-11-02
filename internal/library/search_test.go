package library

import (
	"testing"

	"github.com/mint-bookshelf/mint-bookshelf/internal/storage"
)

func TestFilterBooks(t *testing.T) {
	books := []storage.Book{
		{Title: "Alpha", Author: "Bob", Format: "epub"},
		{Title: "Beta", Author: "Alice", Format: "pdf"},
	}
	got := FilterBooks(books, "alice")
	if len(got) != 1 || got[0].Title != "Beta" {
		t.Fatalf("got %+v", got)
	}
	if len(FilterBooks(books, "")) != 2 {
		t.Fatal("empty filter")
	}
}

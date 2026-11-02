package library

import (
	"strings"

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func FilterBooks(books []storage.Book, query string) []storage.Book {
	if query == "" {
		return books
	}
	q := strings.ToLower(query)
	var out []storage.Book
	for _, b := range books {
		if strings.Contains(strings.ToLower(b.Title), q) ||
			strings.Contains(strings.ToLower(b.Author), q) ||
			strings.Contains(strings.ToLower(b.Series), q) ||
			strings.Contains(strings.ToLower(b.Format), q) {
			out = append(out, b)
		}
	}
	if out == nil {
		out = []storage.Book{}
	}
	return out
}

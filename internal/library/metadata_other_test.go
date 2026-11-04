package library

import "testing"

func TestParseEbookMeta(t *testing.T) {
	fields := parseEbookMeta(`Title               : Book
Author(s)           : Alice & Bob
Publisher           : Pub
Languages           : ru
ISBN                : 978123
Tags                : one, two
Series              : Cycle #2.5
Comments            : Description
`)
	if fields["Title"] != "Book" || fields["Author(s)"] != "Alice & Bob" {
		t.Fatalf("fields = %+v", fields)
	}
	if fields["Series"] != "Cycle" || fields["SeriesIndex"] != "2.5" {
		t.Fatalf("series = %+v", fields)
	}
	if fields["ISBN"] != "978123" || fields["Languages"] != "ru" {
		t.Fatalf("fields = %+v", fields)
	}
}

func TestIsPlaceholderAuthor(t *testing.T) {
	for _, value := range []string{"Unknown", "unknown author", " N/A ", "none"} {
		if !isPlaceholderAuthor(value) {
			t.Fatalf("%q should be a placeholder", value)
		}
	}
	if isPlaceholderAuthor("Ivan Petrov") {
		t.Fatal("real author marked as placeholder")
	}
}

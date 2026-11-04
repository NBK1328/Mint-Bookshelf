package library

import (
	"archive/zip"
	"os"
	"path/filepath"
	"testing"

	"github.com/mint-bookshelf/mint-bookshelf/internal/storage"
	"golang.org/x/text/encoding/charmap"
)

func TestParseOPFEPUB3(t *testing.T) {
	book := &storage.Book{Path: "/tmp/book.epub"}
	opf := `<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Title</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:publisher>Test Publisher</dc:publisher>
    <dc:description>Description</dc:description>
    <dc:identifier>urn:isbn:9781234567890</dc:identifier>
    <meta name="calibre:series" content="Series"/>
    <meta name="calibre:series_index" content="2.5"/>
  </metadata>
  <manifest>
    <item id="cover" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
  </manifest>
</package>`

	parseOPF(book, opf, "OEBPS")

	if book.Title != "Test Title" || book.Author != "Test Author" {
		t.Fatalf("title/author = %q/%q", book.Title, book.Author)
	}
	if book.ISBN != "9781234567890" {
		t.Fatalf("isbn = %q", book.ISBN)
	}
	if book.Series != "Series" || book.SeriesIndex != 2.5 {
		t.Fatalf("series = %q/%v", book.Series, book.SeriesIndex)
	}
	wantCover := "zip:///tmp/book.epub!OEBPS/images/cover.jpg"
	if book.CoverPath != wantCover {
		t.Fatalf("cover = %q, want %q", book.CoverPath, wantCover)
	}
}

func TestParseOPFCoverMeta(t *testing.T) {
	book := &storage.Book{Path: "/tmp/book.epub"}
	opf := `<package>
  <metadata><meta name="cover" content="img"/></metadata>
  <manifest>
    <item id="img" href="cover.png" media-type="image/png"/>
    <item id="other" href="other.png" media-type="image/png"/>
  </manifest>
</package>`

	parseOPF(book, opf, "")
	if book.CoverPath != "zip:///tmp/book.epub!cover.png" {
		t.Fatalf("cover = %q", book.CoverPath)
	}
}

func TestReadFB2Metadata(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "book.fb2")
	data := `<FictionBook>
  <description>
    <title-info>
      <book-title>FB2 Title</book-title>
      <author><first-name>Ivan</first-name><last-name>Petrov</last-name></author>
      <author><nickname>Second</nickname></author>
      <sequence name="Series" number="3"/>
    </title-info>
    <publish-info><publisher>Publisher</publisher><year>2024</year></publish-info>
    <document-info><isbn>9780000000000</isbn></document-info>
  </description>
</FictionBook>`
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	book := &storage.Book{Path: path, Format: "fb2"}
	readFB2Metadata(book)
	if book.Title != "FB2 Title" {
		t.Fatalf("title = %q", book.Title)
	}
	if book.Author != "Ivan Petrov, Second" {
		t.Fatalf("author = %q", book.Author)
	}
	if book.Series != "Series" || book.SeriesIndex != 3 {
		t.Fatalf("series = %q/%v", book.Series, book.SeriesIndex)
	}
	if book.Publisher != "Publisher" || book.Year != 2024 || book.ISBN != "9780000000000" {
		t.Fatalf("publish = %+v", book)
	}
}

func TestReadFB2Cover(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "cover.fb2")
	data := `<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
  <description><title-info><book-title>Covered</book-title><coverpage><image l:href="#cover.jpg"/></coverpage></title-info></description>
  <binary id="cover.jpg" content-type="image/jpeg">Y292ZXItYnl0ZXM=</binary>
</FictionBook>`
	if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	book := &storage.Book{Path: path, Format: "fb2"}
	readFB2Metadata(book)
	if book.CoverPath == "" {
		t.Fatal("cover was not extracted")
	}
	defer os.Remove(book.CoverPath)
	if filepath.Ext(book.CoverPath) != ".jpg" {
		t.Fatalf("cover ext = %q", filepath.Ext(book.CoverPath))
	}
	got, err := os.ReadFile(book.CoverPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "cover-bytes" {
		t.Fatalf("cover bytes = %q", got)
	}
}

func TestReadFB2Windows1251(t *testing.T) {
	xmlText := `<?xml version="1.0" encoding="windows-1251"?><FictionBook><description><title-info><book-title>Тест</book-title><author><first-name>Иван</first-name><last-name>Петров</last-name></author></title-info></description></FictionBook>`
	encoded, err := charmap.Windows1251.NewEncoder().Bytes([]byte(xmlText))
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "cp1251.fb2")
	if err := os.WriteFile(path, encoded, 0o644); err != nil {
		t.Fatal(err)
	}
	book := &storage.Book{Path: path, Format: "fb2"}
	readFB2Metadata(book)
	if book.Title != "Тест" {
		t.Fatalf("title = %q", book.Title)
	}
	if book.Author != "Иван Петров" {
		t.Fatalf("author = %q", book.Author)
	}
}

func TestEPUBFallbackCoverExtraction(t *testing.T) {
	dir := t.TempDir()
	epubPath := filepath.Join(dir, "fallback.epub")
	f, err := os.Create(epubPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	write := func(name, content string) {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	write("META-INF/container.xml", `<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>`)
	write("content.opf", `<package><metadata><title>Fallback</title></metadata><manifest></manifest></package>`)
	write("images/picture.jpg", "image-bytes")
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	book := &storage.Book{Path: epubPath, Format: "epub"}
	readEPUBMetadata(book)
	if book.CoverPath == "" {
		t.Fatal("fallback cover was not detected")
	}
	ExtractCovers(book)
	if book.CoverPath == "" {
		t.Fatal("fallback cover was not extracted")
	}
	defer os.Remove(book.CoverPath)
	if _, err := os.Stat(book.CoverPath); err != nil {
		t.Fatal(err)
	}
}

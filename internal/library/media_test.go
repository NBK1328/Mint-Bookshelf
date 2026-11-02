package library

import (
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestCoverCacheKeyUsesFullPath(t *testing.T) {
	a := cacheKey("/books/a/book.epub")
	b := cacheKey("/books/b/book.epub")
	if a == b {
		t.Fatal("cover cache key must distinguish same basename in different folders")
	}
}

func TestThumbnailExtremeAspect(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "wide.png")
	img := image.NewRGBA(image.Rect(0, 0, 10_000, 1))
	img.Set(0, 0, color.White)
	f, err := os.Create(src)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(f, img); err != nil {
		f.Close()
		t.Fatal(err)
	}
	f.Close()

	out, err := Thumbnail(src, 64)
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(out)

	decoded, err := os.Open(out)
	if err != nil {
		t.Fatal(err)
	}
	defer decoded.Close()
	thumb, _, err := image.Decode(decoded)
	if err != nil {
		t.Fatal(err)
	}
	bounds := thumb.Bounds()
	if bounds.Dx() != 64 || bounds.Dy() != 1 {
		t.Fatalf("thumbnail bounds = %v", bounds)
	}
}

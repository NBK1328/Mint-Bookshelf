package library

import (
	"image"
	"image/png"
	"os"
	"path/filepath"

	_ "image/jpeg"
	_ "image/png"
)

func Thumbnail(src string, max int) (string, error) {
	if max <= 0 {
		max = 256
	}
	f, err := os.Open(src)
	if err != nil {
		return "", err
	}
	defer f.Close()
	img, _, err := image.Decode(f)
	if err != nil {
		return "", err
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w > max || h > max {
		if w >= h {
			h = h * max / w
			w = max
		} else {
			w = w * max / h
			h = max
		}
	}
	outImg := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			sx := b.Min.X + x*b.Dx()/w
			sy := b.Min.Y + y*b.Dy()/h
			outImg.Set(x, y, img.At(sx, sy))
		}
	}
	out := filepath.Join(CacheDir(), "thumb_"+filepath.Base(src)+".png")
	of, err := os.Create(out)
	if err != nil {
		return "", err
	}
	defer of.Close()
	if err := png.Encode(of, outImg); err != nil {
		return "", err
	}
	return out, nil
}

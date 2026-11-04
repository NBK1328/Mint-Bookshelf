package library

import (
	"archive/zip"
	"bytes"
	"encoding/base64"
	"encoding/xml"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/mint-bookshelf/mint-bookshelf/internal/storage"
	"golang.org/x/text/encoding/charmap"
)

var containerPathRE = regexp.MustCompile(`full-path\s*=\s*["']([^"']+)["']`)

func readEPUBMetadata(b *storage.Book) {
	zr, err := zip.OpenReader(b.Path)
	if err != nil {
		return
	}
	defer zr.Close()

	var opfPath string
	for _, f := range zr.File {
		if f.Name != "META-INF/container.xml" {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return
		}
		data, _ := io.ReadAll(rc)
		rc.Close()
		if m := containerPathRE.FindSubmatch(data); len(m) > 1 {
			opfPath = string(m[1])
		}
		break
	}
	if opfPath == "" {
		return
	}

	for _, f := range zr.File {
		if f.Name != opfPath {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return
		}
		data, _ := io.ReadAll(rc)
		rc.Close()
		parseOPF(b, string(data), filepath.Dir(opfPath))
		if b.CoverPath == "" {
			if entry := firstImageEntry(zr); entry != "" {
				b.CoverPath = "zip://" + b.Path + "!" + entry
			}
		}
		return
	}
}

type opfPackage struct {
	Metadata struct {
		Title       []string `xml:"title"`
		Creator     []string `xml:"creator"`
		Description []string `xml:"description"`
		Language    []string `xml:"language"`
		Publisher   []string `xml:"publisher"`
		Identifier  []struct {
			Scheme string `xml:"scheme,attr"`
			Value  string `xml:",chardata"`
		} `xml:"identifier"`
		Meta []struct {
			Name    string `xml:"name,attr"`
			Content string `xml:"content,attr"`
		} `xml:"meta"`
	} `xml:"metadata"`
	Manifest struct {
		Items []struct {
			ID         string `xml:"id,attr"`
			Href       string `xml:"href,attr"`
			MediaType  string `xml:"media-type,attr"`
			Properties string `xml:"properties,attr"`
		} `xml:"item"`
	} `xml:"manifest"`
}

func parseOPF(b *storage.Book, data string, base string) {
	var pkg opfPackage
	if err := xml.Unmarshal([]byte(data), &pkg); err != nil {
		return
	}
	if len(pkg.Metadata.Title) > 0 {
		b.Title = strings.TrimSpace(pkg.Metadata.Title[0])
	}
	if len(pkg.Metadata.Creator) > 0 {
		b.Author = strings.TrimSpace(pkg.Metadata.Creator[0])
	}
	if len(pkg.Metadata.Description) > 0 {
		b.Description = strings.TrimSpace(pkg.Metadata.Description[0])
	}
	if len(pkg.Metadata.Language) > 0 {
		b.Language = strings.TrimSpace(pkg.Metadata.Language[0])
	}
	if len(pkg.Metadata.Publisher) > 0 {
		b.Publisher = strings.TrimSpace(pkg.Metadata.Publisher[0])
	}
	for _, id := range pkg.Metadata.Identifier {
		value := strings.TrimSpace(id.Value)
		lower := strings.ToLower(value)
		switch {
		case strings.EqualFold(id.Scheme, "ISBN"):
			b.ISBN = value
		case strings.HasPrefix(lower, "urn:isbn:"):
			b.ISBN = strings.TrimSpace(value[len("urn:isbn:"):])
		}
	}
	for _, meta := range pkg.Metadata.Meta {
		switch meta.Name {
		case "calibre:series":
			b.Series = strings.TrimSpace(meta.Content)
		case "calibre:series_index":
			var index float64
			fmt.Sscanf(meta.Content, "%f", &index)
			b.SeriesIndex = index
		}
	}

	if href := coverHref(pkg); href != "" {
		full := href
		if base != "" && base != "." {
			full = base + "/" + href
		}
		full = strings.TrimPrefix(filepath.Clean(full), "./")
		b.CoverPath = "zip://" + b.Path + "!" + full
	}
}

func firstImageEntry(zr *zip.ReadCloser) string {
	fallback := ""
	for _, file := range zr.File {
		if strings.HasPrefix(file.Name, "META-INF/") {
			continue
		}
		switch strings.ToLower(filepath.Ext(file.Name)) {
		case ".jpg", ".jpeg", ".png", ".gif", ".webp":
			if strings.Contains(strings.ToLower(file.Name), "cover") {
				return file.Name
			}
			if fallback == "" {
				fallback = file.Name
			}
		}
	}
	return fallback
}

func coverHref(pkg opfPackage) string {
	coverID := ""
	for _, meta := range pkg.Metadata.Meta {
		if meta.Name == "cover" {
			coverID = strings.TrimSpace(meta.Content)
		}
	}

	for _, item := range pkg.Manifest.Items {
		if strings.Contains(item.Properties, "cover-image") {
			return item.Href
		}
	}
	if coverID != "" {
		for _, item := range pkg.Manifest.Items {
			if item.ID == coverID {
				return item.Href
			}
		}
	}
	for _, item := range pkg.Manifest.Items {
		if !strings.HasPrefix(strings.ToLower(item.MediaType), "image/") {
			continue
		}
		if strings.Contains(strings.ToLower(item.ID), "cover") ||
			strings.Contains(strings.ToLower(item.Href), "cover") {
			return item.Href
		}
	}
	return ""
}

type fb2Author struct {
	First  string `xml:"first-name"`
	Middle string `xml:"middle-name"`
	Last   string `xml:"last-name"`
	Nick   string `xml:"nickname"`
}

type fb2Coverpage struct {
	Image struct {
		Href string `xml:"href,attr"`
	} `xml:"image"`
}

type fb2TitleInfo struct {
	BookTitle string       `xml:"book-title"`
	Authors   []fb2Author  `xml:"author"`
	Coverpage fb2Coverpage `xml:"coverpage"`
	Sequence  struct {
		Name   string `xml:"name,attr"`
		Number string `xml:"number,attr"`
	} `xml:"sequence"`
}

type fb2Binary struct {
	ID          string `xml:"id,attr"`
	ContentType string `xml:"content-type,attr"`
	Data        string `xml:",chardata"`
}

type fb2 struct {
	Desc struct {
		TitleInfo    fb2TitleInfo `xml:"title-info"`
		SrcTitleInfo fb2TitleInfo `xml:"src-title-info"`
		PublishInfo  struct {
			Publisher string `xml:"publisher"`
			Year      string `xml:"year"`
		} `xml:"publish-info"`
		DocumentInfo struct {
			ISBN string `xml:"isbn"`
		} `xml:"document-info"`
	} `xml:"description"`
	Coverpage fb2Coverpage `xml:"coverpage"`
	Binaries  []fb2Binary  `xml:"binary"`
}

func newFB2Decoder(data []byte) *xml.Decoder {
	data = bytes.TrimPrefix(data, []byte{0xEF, 0xBB, 0xBF})
	dec := xml.NewDecoder(bytes.NewReader(data))
	dec.CharsetReader = func(label string, input io.Reader) (io.Reader, error) {
		switch strings.ToLower(strings.TrimSpace(label)) {
		case "windows-1251", "cp1251":
			return charmap.Windows1251.NewDecoder().Reader(input), nil
		case "koi8-r", "koi8r":
			return charmap.KOI8R.NewDecoder().Reader(input), nil
		case "windows-1252", "cp1252":
			return charmap.Windows1252.NewDecoder().Reader(input), nil
		case "iso-8859-1", "latin1":
			return charmap.ISO8859_1.NewDecoder().Reader(input), nil
		case "iso-8859-5":
			return charmap.ISO8859_5.NewDecoder().Reader(input), nil
		case "ibm866", "cp866":
			return charmap.CodePage866.NewDecoder().Reader(input), nil
		case "us-ascii", "ascii":
			return input, nil
		}
		return nil, fmt.Errorf("unsupported charset %q", label)
	}
	return dec
}

func readFB2Metadata(b *storage.Book) {
	data, err := os.ReadFile(b.Path)
	if err != nil {
		return
	}
	var f fb2
	if err := newFB2Decoder(data).Decode(&f); err != nil {
		return
	}

	titleInfo := f.Desc.TitleInfo
	if titleInfo.BookTitle == "" && len(titleInfo.Authors) == 0 {
		titleInfo = f.Desc.SrcTitleInfo
	}
	if titleInfo.BookTitle != "" {
		b.Title = strings.TrimSpace(titleInfo.BookTitle)
	}
	var authors []string
	for _, author := range titleInfo.Authors {
		var parts []string
		for _, part := range []string{author.First, author.Middle, author.Last} {
			if part = strings.TrimSpace(part); part != "" {
				parts = append(parts, part)
			}
		}
		name := strings.Join(parts, " ")
		if name == "" {
			name = strings.TrimSpace(author.Nick)
		}
		if name != "" {
			authors = append(authors, name)
		}
	}
	if len(authors) > 0 {
		b.Author = strings.Join(authors, ", ")
	}
	if titleInfo.Sequence.Name != "" {
		b.Series = strings.TrimSpace(titleInfo.Sequence.Name)
		var index float64
		fmt.Sscanf(titleInfo.Sequence.Number, "%f", &index)
		b.SeriesIndex = index
	}
	b.Publisher = strings.TrimSpace(f.Desc.PublishInfo.Publisher)
	fmt.Sscanf(f.Desc.PublishInfo.Year, "%d", &b.Year)
	b.ISBN = strings.TrimSpace(f.Desc.DocumentInfo.ISBN)
	extractFB2Cover(b, &f, titleInfo.Coverpage)
}

func extractFB2Cover(b *storage.Book, f *fb2, coverpage fb2Coverpage) {
	href := strings.TrimSpace(coverpage.Image.Href)
	if href == "" {
		href = strings.TrimSpace(f.Coverpage.Image.Href)
	}
	if !strings.HasPrefix(href, "#") {
		return
	}
	id := strings.TrimPrefix(href, "#")
	for _, bin := range f.Binaries {
		if strings.TrimSpace(bin.ID) != id {
			continue
		}
		encoded := strings.Join(strings.Fields(bin.Data), "")
		if encoded == "" {
			return
		}
		content, err := base64.StdEncoding.DecodeString(encoded)
		if err != nil || len(content) == 0 {
			return
		}
		dest := filepath.Join(CacheDir(), cacheKeyForBook(b)+fb2CoverExt(bin.ContentType, id))
		if info, err := os.Stat(dest); err == nil && info.Size() > 0 {
			b.CoverPath = dest
			return
		}
		if err := os.WriteFile(dest, content, 0o644); err != nil {
			return
		}
		b.CoverPath = dest
		return
	}
}

func fb2CoverExt(contentType, id string) string {
	switch strings.ToLower(strings.TrimSpace(contentType)) {
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "image/bmp":
		return ".bmp"
	}
	switch ext := strings.ToLower(filepath.Ext(id)); ext {
	case ".jpg", ".jpeg":
		return ".jpg"
	case ".png", ".gif", ".webp", ".bmp":
		return ext
	}
	return ".jpg"
}

func ExtractCoverZip(zipPath, entry string, dest string) error {
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer zr.Close()
	for _, f := range zr.File {
		if f.Name != entry {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		defer rc.Close()
		out, err := os.Create(dest)
		if err != nil {
			return err
		}
		defer out.Close()
		_, err = io.Copy(out, rc)
		return err
	}
	return fmt.Errorf("entry not found")
}

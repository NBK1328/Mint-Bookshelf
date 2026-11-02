package library

import (
	"archive/zip"
	"encoding/xml"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/mint-bookshelf/mint-bookshelf/internal/storage"
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

type fb2TitleInfo struct {
	BookTitle string      `xml:"book-title"`
	Authors   []fb2Author `xml:"author"`
	Sequence  struct {
		Name   string `xml:"name,attr"`
		Number string `xml:"number,attr"`
	} `xml:"sequence"`
}

type fb2 struct {
	Desc struct {
		TitleInfo   fb2TitleInfo `xml:"title-info"`
		PublishInfo struct {
			Publisher string `xml:"publisher"`
			Year      string `xml:"year"`
		} `xml:"publish-info"`
		DocumentInfo struct {
			ISBN string `xml:"isbn"`
		} `xml:"document-info"`
	} `xml:"description"`
}

func readFB2Metadata(b *storage.Book) {
	data, err := os.ReadFile(b.Path)
	if err != nil {
		return
	}
	var f fb2
	if err := xml.Unmarshal(data, &f); err != nil {
		return
	}

	titleInfo := f.Desc.TitleInfo
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

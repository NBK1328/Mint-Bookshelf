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

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func readEPUBMetadata(b *storage.Book) {
	zr, err := zip.OpenReader(b.Path)
	if err != nil {
		return
	}
	defer zr.Close()
	// find container.xml
	var opfPath string
	for _, f := range zr.File {
		if f.Name == "META-INF/container.xml" {
			rc, err := f.Open()
			if err != nil {
				return
			}
			data, _ := io.ReadAll(rc)
			rc.Close()
			re := regexp.MustCompile(`full-path="([^"]+)"`)
			m := re.FindSubmatch(data)
			if len(m) > 1 {
				opfPath = string(m[1])
			}
		}
	}
	if opfPath == "" {
		return
	}
	for _, f := range zr.File {
		if f.Name == opfPath {
			rc, err := f.Open()
			if err != nil {
				return
			}
			data, _ := io.ReadAll(rc)
			rc.Close()
			parseOPF(b, string(data), filepath.Dir(opfPath), zr)
		}
	}
}

type opfMeta struct {
	Title   string `xml:"title"`
	Creator string `xml:"creator"`
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
}

func parseOPF(b *storage.Book, data string, base string, zr *zip.ReadCloser) {
	var pkg opfPackage
	if err := xml.Unmarshal([]byte(data), &pkg); err != nil {
		return
	}
	if len(pkg.Metadata.Title) > 0 {
		b.Title = pkg.Metadata.Title[0]
	}
	if len(pkg.Metadata.Creator) > 0 {
		b.Author = pkg.Metadata.Creator[0]
	}
	if len(pkg.Metadata.Description) > 0 {
		b.Description = pkg.Metadata.Description[0]
	}
	if len(pkg.Metadata.Language) > 0 {
		b.Language = pkg.Metadata.Language[0]
	}
	if len(pkg.Metadata.Publisher) > 0 {
		b.Publisher = pkg.Metadata.Publisher[0]
	}
	for _, id := range pkg.Metadata.Identifier {
		if strings.EqualFold(id.Scheme, "ISBN") {
			b.ISBN = strings.TrimSpace(id.Value)
		}
	}
	for _, m := range pkg.Metadata.Meta {
		switch m.Name {
		case "calibre:series":
			b.Series = m.Content
		case "calibre:series_index":
			// parse float
			var f float64
			fmt.Sscanf(m.Content, "%f", &f)
			b.SeriesIndex = f
		}
	}
	// cover image
	re := regexp.MustCompile(`<meta[^>]*name="cover"[^>]*content="([^"]+)"`)
	m := re.FindStringSubmatch(data)
	if len(m) > 1 {
		id := m[1]
		// find item with id
		re2 := regexp.MustCompile(`<item[^>]*id="` + regexp.QuoteMeta(id) + `"[^>]*href="([^"]+)"`)
		m2 := re2.FindStringSubmatch(data)
		if len(m2) > 1 {
			href := m2[1]
			full := href
			if base != "" && base != "." {
				full = base + "/" + href
			}
			full = filepath.Clean(full)
			full = strings.TrimPrefix(full, "./")
			b.CoverPath = "zip://" + b.Path + "!" + full
		}
	}
}

func readFB2Metadata(b *storage.Book) {
	data, err := os.ReadFile(b.Path)
	if err != nil {
		return
	}
	type titleInfo struct {
		BookTitle string `xml:"book-title"`
		Author    struct {
			FirstName string `xml:"first-name"`
			LastName  string `xml:"last-name"`
		} `xml:"author"`
		Sequence struct {
			Name   string `xml:"name,attr"`
			Number string `xml:"number,attr"`
		} `xml:"sequence"`
	}
	type fb2 struct {
		Desc struct {
			TitleInfo titleInfo `xml:"title-info"`
		} `xml:"description"`
	}
	var f fb2
	if err := xml.Unmarshal(data, &f); err != nil {
		return
	}
	if f.Desc.TitleInfo.BookTitle != "" {
		b.Title = f.Desc.TitleInfo.BookTitle
	}
	author := strings.TrimSpace(f.Desc.TitleInfo.Author.FirstName + " " + f.Desc.TitleInfo.Author.LastName)
	if author != "" {
		b.Author = author
	}
	if f.Desc.TitleInfo.Sequence.Name != "" {
		b.Series = f.Desc.TitleInfo.Sequence.Name
	}
	if f.Desc.TitleInfo.Sequence.Name != "" {
		b.Series = f.Desc.TitleInfo.Sequence.Name
	}
}

// helper for cover extraction later
func ExtractCoverZip(zipPath, entry string, dest string) error {
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer zr.Close()
	for _, f := range zr.File {
		if f.Name == entry {
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
	}
	return fmt.Errorf("entry not found")
}

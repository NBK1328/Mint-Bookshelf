package library

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func readCalibreMetadata(b *storage.Book) {
	path := findEbookMeta()
	if path == "" {
		return
	}
	out, err := exec.Command(path, b.Path).Output()
	if err != nil {
		return
	}
	fields := parseEbookMeta(string(out))
	if value := fields["Title"]; value != "" {
		b.Title = value
	}
	if value := fields["Author(s)"]; value != "" {
		b.Author = value
	}
	if value := fields["Publisher"]; value != "" {
		b.Publisher = value
	}
	if value := fields["Languages"]; value != "" {
		b.Language = value
	}
	if value := fields["ISBN"]; value != "" {
		b.ISBN = value
	}
	if value := fields["Comments"]; value != "" {
		b.Description = value
	}
	if value := fields["Tags"]; value != "" {
		b.Tags = value
	}
	if value := fields["Series"]; value != "" {
		b.Series = value
	}
	if value := fields["SeriesIndex"]; value != "" {
		var index float64
		fmt.Sscanf(value, "%f", &index)
		b.SeriesIndex = index
	}
}

func findEbookMeta() string {
	if path, err := exec.LookPath("ebook-meta"); err == nil {
		return path
	}
	for _, path := range []string{
		"/Applications/calibre.app/Contents/MacOS/ebook-meta",
		"/opt/homebrew/bin/ebook-meta",
	} {
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}

func parseEbookMeta(output string) map[string]string {
	fields := map[string]string{}
	for _, line := range strings.Split(output, "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if key == "" || value == "" {
			continue
		}
		fields[key] = value
	}
	if series := fields["Series"]; series != "" {
		if name, number, ok := strings.Cut(series, "#"); ok {
			fields["Series"] = strings.TrimSpace(name)
			var index float64
			fmt.Sscanf(strings.TrimSpace(number), "%f", &index)
			fields["SeriesIndex"] = fmt.Sprintf("%g", index)
		}
	}
	return fields
}

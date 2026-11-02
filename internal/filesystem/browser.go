package filesystem

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Entry struct {
	Name     string `json:"name"`
	Path     string `json:"path"`
	IsDir    bool   `json:"isDir"`
	Size     int64  `json:"size"`
	Modified int64  `json:"modified"`
}

func ListDir(path string) ([]Entry, error) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, err
	}
	var out []Entry
	for _, e := range entries {
		info, _ := e.Info()
		size := int64(0)
		modified := int64(0)
		if info != nil {
			size = info.Size()
			modified = info.ModTime().Unix()
		}
		out = append(out, Entry{
			Name:     e.Name(),
			Path:     filepath.Join(path, e.Name()),
			IsDir:    e.IsDir(),
			Size:     size,
			Modified: modified,
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].IsDir != out[j].IsDir {
			return out[i].IsDir
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out, nil
}

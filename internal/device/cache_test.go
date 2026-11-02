package device

import "testing"

func TestKnownFolderCache(t *testing.T) {
	s := &Session{knownFolders: map[objectKey]FileEntry{}}
	s.rememberFolder(FileEntry{ID: 1, Name: "A", StorageID: 7, IsFolder: true})
	s.rememberFolder(FileEntry{ID: 2, Name: "B", StorageID: 7, IsFolder: true})

	byID := make(map[uint32]FileEntry)
	for _, f := range s.knownFolderSnapshot() {
		byID[f.ID] = f
	}
	if len(byID) != 2 || byID[1].Name != "A" || byID[2].Name != "B" {
		t.Fatalf("snapshot = %+v", byID)
	}

	s.updateKnownFolder(1, func(f *FileEntry) {
		f.Name = "Renamed"
		f.ParentID = 2
	})
	s.forgetFolder(2)

	byID = make(map[uint32]FileEntry)
	for _, f := range s.knownFolderSnapshot() {
		byID[f.ID] = f
	}
	if len(byID) != 1 {
		t.Fatalf("snapshot = %+v", byID)
	}
	if byID[1].Name != "Renamed" || byID[1].ParentID != 2 {
		t.Fatalf("updated folder = %+v", byID[1])
	}
}

package storage

import "time"

type Book struct {
	ID          int64     `json:"id"`
	Title       string    `json:"title"`
	Author      string    `json:"author"`
	Series      string    `json:"series"`
	SeriesIndex float64   `json:"seriesIndex"`
	Publisher   string    `json:"publisher"`
	Year        int       `json:"year"`
	Language    string    `json:"language"`
	ISBN        string    `json:"isbn"`
	Description string    `json:"description"`
	Tags        string    `json:"tags"`
	Format      string    `json:"format"`
	Size        int64     `json:"size"`
	Path        string    `json:"path"`
	CoverPath   string    `json:"coverPath"`
	AddedAt     time.Time `json:"addedAt"`
	ModifiedAt  time.Time `json:"modifiedAt"`
	Fingerprint string    `json:"fingerprint"`
	Deleted     bool      `json:"deleted"`
}

type LibraryRoot struct {
	ID   int64
	Path string
}

type Operation struct {
	ID        string     `json:"id"`
	Type      string     `json:"type"`
	Status    string     `json:"status"`
	Title     string     `json:"title"`
	Progress  float64    `json:"progress"`
	StartedAt *time.Time `json:"startedAt,omitempty"`
	EndedAt   *time.Time `json:"endedAt,omitempty"`
	Error     string     `json:"error,omitempty"`
}

type DeviceFolder struct {
	DeviceKey string
	StorageID uint32
	ObjectID  uint32
	ParentID  uint32
	Name      string
}

package storage

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

type DB struct {
	sql *sql.DB
}

func Open(path string) (*DB, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	d := &DB{sql: db}
	if err := d.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	return d, nil
}

func (d *DB) Close() error { return d.sql.Close() }

func (d *DB) migrate() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS books (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			title TEXT NOT NULL DEFAULT '',
			author TEXT NOT NULL DEFAULT '',
			series TEXT NOT NULL DEFAULT '',
			series_index REAL NOT NULL DEFAULT 0,
			publisher TEXT NOT NULL DEFAULT '',
			year INTEGER NOT NULL DEFAULT 0,
			language TEXT NOT NULL DEFAULT '',
			isbn TEXT NOT NULL DEFAULT '',
			description TEXT NOT NULL DEFAULT '',
			tags TEXT NOT NULL DEFAULT '',
			format TEXT NOT NULL DEFAULT '',
			size INTEGER NOT NULL DEFAULT 0,
			path TEXT NOT NULL UNIQUE,
			cover_path TEXT NOT NULL DEFAULT '',
			added_at INTEGER NOT NULL DEFAULT 0,
			modified_at INTEGER NOT NULL DEFAULT 0,
			fingerprint TEXT NOT NULL DEFAULT '',
			deleted INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE INDEX IF NOT EXISTS idx_books_title ON books(title)`,
		`CREATE INDEX IF NOT EXISTS idx_books_author ON books(author)`,
		`CREATE TABLE IF NOT EXISTS library_roots (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			path TEXT NOT NULL UNIQUE
		)`,
		`CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT '')`,
		`CREATE TABLE IF NOT EXISTS operations (
			id TEXT PRIMARY KEY,
			type TEXT NOT NULL,
			status TEXT NOT NULL,
			title TEXT NOT NULL DEFAULT '',
			progress REAL NOT NULL DEFAULT 0,
			started_at INTEGER,
			ended_at INTEGER,
			error TEXT NOT NULL DEFAULT ''
		)`,
	}
	for _, s := range stmts {
		if _, err := d.sql.Exec(s); err != nil {
			return fmt.Errorf("migrate: %w", err)
		}
	}
	return nil
}

func (d *DB) AddRoot(path string) error {
	_, err := d.sql.Exec(`INSERT OR IGNORE INTO library_roots(path) VALUES(?)`, path)
	return err
}

func (d *DB) Roots() ([]string, error) {
	var out []string
	rows, err := d.sql.Query(`SELECT path FROM library_roots`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (d *DB) UpsertBook(b *Book) error {
	_, err := d.sql.Exec(`INSERT INTO books(title,author,series,series_index,publisher,year,language,isbn,description,tags,format,size,path,cover_path,added_at,modified_at,fingerprint,deleted)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(path) DO UPDATE SET
		title=excluded.title,author=excluded.author,series=excluded.series,series_index=excluded.series_index,publisher=excluded.publisher,year=excluded.year,language=excluded.language,isbn=excluded.isbn,description=excluded.description,tags=excluded.tags,format=excluded.format,size=excluded.size,cover_path=excluded.cover_path,modified_at=excluded.modified_at,fingerprint=excluded.fingerprint,deleted=excluded.deleted`,
		b.Title, b.Author, b.Series, b.SeriesIndex, b.Publisher, b.Year, b.Language, b.ISBN, b.Description, b.Tags, b.Format, b.Size, b.Path, b.CoverPath, b.AddedAt.Unix(), b.ModifiedAt.Unix(), b.Fingerprint, boolToInt(b.Deleted))
	return err
}

func (d *DB) Books() ([]Book, error) {
	rows, err := d.sql.Query(`SELECT id,title,author,series,series_index,publisher,year,language,isbn,description,tags,format,size,path,cover_path,added_at,modified_at,fingerprint,deleted FROM books WHERE deleted=0`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Book
	for rows.Next() {
		var b Book
		var added, modified int64
		var del int
		if err := rows.Scan(&b.ID, &b.Title, &b.Author, &b.Series, &b.SeriesIndex, &b.Publisher, &b.Year, &b.Language, &b.ISBN, &b.Description, &b.Tags, &b.Format, &b.Size, &b.Path, &b.CoverPath, &added, &modified, &b.Fingerprint, &del); err != nil {
			return nil, err
		}
		b.AddedAt = time.Unix(added, 0)
		b.ModifiedAt = time.Unix(modified, 0)
		b.Deleted = del != 0
		out = append(out, b)
	}
	return out, rows.Err()
}

func (d *DB) DeleteBookPath(path string) error {
	_, err := d.sql.Exec(`UPDATE books SET deleted=1 WHERE path=?`, path)
	return err
}

func (d *DB) Search(q string) ([]Book, error) {
	// simple
	all, err := d.Books()
	if err != nil {
		return nil, err
	}
	if q == "" {
		return all, nil
	}
	var out []Book
	for _, b := range all {
		if containsFold(b.Title, q) || containsFold(b.Author, q) || containsFold(b.Series, q) {
			out = append(out, b)
		}
	}
	return out, nil
}


func (d *DB) SetSetting(key, value string) error {
	_, err := d.sql.Exec(`INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, key, value)
	return err
}

func (d *DB) GetSetting(key string) (string, error) {
	var v string
	err := d.sql.QueryRow(`SELECT value FROM settings WHERE key=?`, key).Scan(&v)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return v, err
}


func (d *DB) UpsertOperation(o *Operation) error {
	var started, ended *int64
	if o.StartedAt != nil { v := o.StartedAt.Unix(); started = &v }
	if o.EndedAt != nil { v := o.EndedAt.Unix(); ended = &v }
	_, err := d.sql.Exec(`INSERT INTO operations(id,type,status,title,progress,started_at,ended_at,error)
		VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
		type=excluded.type,status=excluded.status,title=excluded.title,progress=excluded.progress,started_at=excluded.started_at,ended_at=excluded.ended_at,error=excluded.error`,
		o.ID, o.Type, o.Status, o.Title, o.Progress, started, ended, o.Error)
	return err
}

func (d *DB) GetOperation(id string) (*Operation, error) {
	row := d.sql.QueryRow(`SELECT id,type,status,title,progress,started_at,ended_at,error FROM operations WHERE id=?`, id)
	var o Operation
	var sp, ep sql.NullInt64
	if err := row.Scan(&o.ID, &o.Type, &o.Status, &o.Title, &o.Progress, &sp, &ep, &o.Error); err != nil {
		// handle nulls by scanning into sql.NullInt64? simpler: retry with coalesce
		return nil, err
	}
	if sp.Valid { t := time.Unix(sp.Int64, 0); o.StartedAt = &t }
	if ep.Valid { t := time.Unix(ep.Int64, 0); o.EndedAt = &t }
	return &o, nil
}

func (d *DB) ListOperations() ([]Operation, error) {
	rows, err := d.sql.Query(`SELECT id,type,status,title,progress,started_at,ended_at,error FROM operations ORDER BY started_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Operation
	for rows.Next() {
		var o Operation
		var sp, ep sql.NullInt64
		if err := rows.Scan(&o.ID, &o.Type, &o.Status, &o.Title, &o.Progress, &sp, &ep, &o.Error); err != nil {
			return nil, err
		}
		if sp.Valid { t := time.Unix(sp.Int64, 0); o.StartedAt = &t }
		if ep.Valid { t := time.Unix(ep.Int64, 0); o.EndedAt = &t }
		out = append(out, o)
	}
	if out == nil {
		out = []Operation{}
	}
	return out, rows.Err()
}

func (d *DB) WithTx(fn func(*sql.Tx) error) error {
	tx, err := d.sql.Begin()
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func containsFold(s, sub string) bool {
	// naive
	return len(sub) == 0 || indexFold(s, sub) >= 0
}

func indexFold(s, sub string) int {
	// simple case-insensitive
	ls := len(s)
	lsub := len(sub)
	if lsub > ls {
		return -1
	}
	for i := 0; i <= ls-lsub; i++ {
		if equalFoldASCII(s[i:i+lsub], sub) {
			return i
		}
	}
	return -1
}

func equalFoldASCII(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i++ {
		ca, cb := a[i], b[i]
		if ca >= 'A' && ca <= 'Z' {
			ca += 32
		}
		if cb >= 'A' && cb <= 'Z' {
			cb += 32
		}
		if ca != cb {
			return false
		}
	}
	return true
}

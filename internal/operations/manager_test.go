package operations

import (
	"context"
	"encoding/json"
	"math"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mint-bookshelf/mint-bookshelf/internal/storage"
)

func waitForStatus(t *testing.T, m *Manager, id string, want Status) TaskSnapshot {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		snapshot, ok := m.Get(id)
		if ok && snapshot.Status == want {
			return snapshot
		}
		time.Sleep(5 * time.Millisecond)
	}
	snapshot, _ := m.Get(id)
	t.Fatalf("status = %s, want %s", snapshot.Status, want)
	return TaskSnapshot{}
}

func TestManagerCompletes(t *testing.T) {
	m := NewManager(2)
	id, err := m.Submit("test", "task", func(ctx context.Context, task *Task) error {
		task.SetProgress(0.5)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	snapshot := waitForStatus(t, m, id, StatusCompleted)
	if snapshot.Progress != 1 {
		t.Fatalf("progress = %v, want 1", snapshot.Progress)
	}
	if snapshot.StartedAt == nil || snapshot.EndedAt == nil {
		t.Fatal("timestamps must be set")
	}
}

func TestManagerCancels(t *testing.T) {
	m := NewManager(2)
	id, err := m.Submit("test", "cancel", func(ctx context.Context, task *Task) error {
		<-ctx.Done()
		return ctx.Err()
	})
	if err != nil {
		t.Fatal(err)
	}
	if !m.Cancel(id) {
		t.Fatal("cancel returned false for active task")
	}
	waitForStatus(t, m, id, StatusCancelled)
	if m.Cancel(id) {
		t.Fatal("cancel returned true for terminal task")
	}
}

func TestManagerRecoversFromPanic(t *testing.T) {
	m := NewManager(1)
	id, err := m.Submit("test", "panic", func(ctx context.Context, task *Task) error {
		panic("boom")
	})
	if err != nil {
		t.Fatal(err)
	}

	snapshot := waitForStatus(t, m, id, StatusFailed)
	if !strings.Contains(snapshot.Error, "panic: boom") {
		t.Fatalf("error = %q", snapshot.Error)
	}
}

func TestProgressClamp(t *testing.T) {
	task := &Task{status: StatusRunning}
	task.SetProgress(-1)
	if got := task.Snapshot().Progress; got != 0 {
		t.Fatalf("progress = %v, want 0", got)
	}
	task.SetProgress(2)
	if got := task.Snapshot().Progress; got != 1 {
		t.Fatalf("progress = %v, want 1", got)
	}
	task.SetProgress(math.NaN())
	if got := task.Snapshot().Progress; got != 1 {
		t.Fatalf("NaN changed progress to %v", got)
	}
}

func TestTaskSnapshotJSON(t *testing.T) {
	m := NewManager(1)
	id, err := m.Submit("convert", "book.epub", func(ctx context.Context, task *Task) error {
		task.SetProgress(0.25)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	snapshot := waitForStatus(t, m, id, StatusCompleted)

	data, err := json.Marshal(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, field := range []string{`"id"`, `"type"`, `"status"`, `"progress"`} {
		if !strings.Contains(text, field) {
			t.Fatalf("JSON %s does not contain %s", text, field)
		}
	}
	if strings.Contains(strings.ToLower(text), "cancel") {
		t.Fatalf("JSON leaks cancel function: %s", text)
	}
}

func TestManagerConcurrentProgress(t *testing.T) {
	m := NewManager(1)
	id, err := m.Submit("test", "progress", func(ctx context.Context, task *Task) error {
		for i := 0; i < 500; i++ {
			task.SetProgress(float64(i) / 500)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	for i := 0; i < 100; i++ {
		_, _ = m.Get(id)
	}
	waitForStatus(t, m, id, StatusCompleted)
}

func TestManagerQueueLimit(t *testing.T) {
	m := NewManager(1)
	m.maxPending = 1
	release := make(chan struct{})

	first, err := m.Submit("test", "first", func(ctx context.Context, task *Task) error {
		<-release
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := m.Submit("test", "second", func(ctx context.Context, task *Task) error {
		return nil
	}); err == nil {
		t.Fatal("expected queue limit error")
	}

	close(release)
	waitForStatus(t, m, first, StatusCompleted)
}

func TestManagerPersistsOperationState(t *testing.T) {
	db, err := storage.Open(filepath.Join(t.TempDir(), "operations.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	m := NewManager(1, db)
	release := make(chan struct{})
	id, err := m.Submit("test", "persisted", func(ctx context.Context, task *Task) error {
		<-release
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	waitForStoredStatus(t, db, id, string(StatusRunning))
	close(release)
	waitForStatus(t, m, id, StatusCompleted)
	waitForStoredStatus(t, db, id, string(StatusCompleted))
}

func waitForStoredStatus(t *testing.T, db *storage.DB, id, want string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		op, err := db.GetOperation(id)
		if err == nil && op.Status == want {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	op, err := db.GetOperation(id)
	t.Fatalf("stored status = %+v, err = %v, want %s", op, err, want)
}

func TestManagerShutdown(t *testing.T) {
	m := NewManager(1)
	id, err := m.Submit("test", "shutdown", func(ctx context.Context, task *Task) error {
		<-ctx.Done()
		return ctx.Err()
	})
	if err != nil {
		t.Fatal(err)
	}

	m.Shutdown(2 * time.Second)
	waitForStatus(t, m, id, StatusCancelled)

	if _, err := m.Submit("test", "after", func(ctx context.Context, task *Task) error {
		return nil
	}); err == nil {
		t.Fatal("expected submit after shutdown to fail")
	}
}

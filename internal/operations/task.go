package operations

import (
	"context"
	"sync"
	"time"

	"github.com/kindle-manager/kindle-manager/internal/storage"

	"github.com/google/uuid"
)

type Status string

const (
	StatusPending   Status = "pending"
	StatusRunning   Status = "running"
	StatusCompleted Status = "completed"
	StatusFailed    Status = "failed"
	StatusCancelled Status = "cancelled"
)

type Task struct {
	ID        string  `json:"id"`
	Type      string  `json:"type"`
	Title     string  `json:"title"`
	Status    Status  `json:"status"`
	Progress  float64 `json:"progress"`
	Error     string
	StartedAt *time.Time
	EndedAt   *time.Time
	Cancel    context.CancelFunc
	ctx       context.Context
	fn        func(ctx context.Context, t *Task) error
}

type Manager struct {
	db      *storage.DB
	mu      sync.Mutex
	tasks   map[string]*Task
	order   []string
	maxConc int
	sem     chan struct{}
}

func NewManager(maxConc int, db ...*storage.DB) *Manager {
	if maxConc < 1 {
		maxConc = 1
	}
	m := &Manager{tasks: map[string]*Task{}, maxConc: maxConc, sem: make(chan struct{}, maxConc)}
	if len(db) > 0 {
		m.db = db[0]
	}
	return m
}

func (m *Manager) Submit(typ, title string, fn func(ctx context.Context, t *Task) error) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	id := uuid.NewString()
	ctx, cancel := context.WithCancel(context.Background())
	t := &Task{ID: id, Type: typ, Title: title, Status: StatusPending, Cancel: cancel, fn: fn}
	t.ctx = ctx
	m.tasks[id] = t
	m.order = append(m.order, id)
	go m.run(t)
	return id
}

// need ctx field
type taskCtx struct{}

func (m *Manager) run(t *Task) {
	m.sem <- struct{}{}
	defer func() { <-m.sem }()
	now := time.Now()
	m.mu.Lock()
	t.Status = StatusRunning
	t.StartedAt = &now
	m.mu.Unlock()
	err := t.fn(t.ctx, t)
	end := time.Now()
	m.mu.Lock()
	t.EndedAt = &end
	if err != nil {
		if t.ctx.Err() != nil {
			t.Status = StatusCancelled
		} else {
			t.Status = StatusFailed
			t.Error = err.Error()
		}
	} else {
		t.Status = StatusCompleted
		t.Progress = 1
	}
	m.mu.Unlock()
	if m.db != nil {
		op := &storage.Operation{ID: t.ID, Type: t.Type, Status: string(t.Status), Title: t.Title, Progress: t.Progress, StartedAt: t.StartedAt, EndedAt: t.EndedAt, Error: t.Error}
		_ = m.db.UpsertOperation(op)
	}
}

func (m *Manager) Get(id string) (*Task, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	t, ok := m.tasks[id]
	return t, ok
}

func (m *Manager) Cancel(id string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	t, ok := m.tasks[id]
	if !ok {
		return false
	}
	if t.Cancel != nil {
		t.Cancel()
	}
	return true
}

func (m *Manager) List() []*Task {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]*Task, 0, len(m.order))
	for _, id := range m.order {
		out = append(out, m.tasks[id])
	}
	return out
}

func (t *Task) SetProgress(p float64) {
	// not thread-safe externally but manager locks not; keep simple
	t.Progress = p
}

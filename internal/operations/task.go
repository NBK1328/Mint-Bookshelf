package operations

import (
	"context"
	"fmt"
	"math"
	"runtime/debug"
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

const (
	defaultMaxTracked = 256
	defaultMaxPending = 128
)

type TaskSnapshot struct {
	ID        string     `json:"id"`
	Type      string     `json:"type"`
	Title     string     `json:"title"`
	Status    Status     `json:"status"`
	Progress  float64    `json:"progress"`
	Error     string     `json:"error,omitempty"`
	StartedAt *time.Time `json:"startedAt,omitempty"`
	EndedAt   *time.Time `json:"endedAt,omitempty"`
}

type Task struct {
	mu        sync.Mutex
	id        string
	typ       string
	title     string
	status    Status
	progress  float64
	err       string
	startedAt *time.Time
	endedAt   *time.Time
	cancel    context.CancelFunc
	ctx       context.Context
	fn        func(context.Context, *Task) error
}

func (t *Task) ID() string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.id
}

func (t *Task) SetProgress(p float64) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.isTerminalLocked() || math.IsNaN(p) {
		return
	}
	if p < 0 {
		p = 0
	}
	if p > 1 {
		p = 1
	}
	t.progress = p
}

func (t *Task) Snapshot() TaskSnapshot {
	t.mu.Lock()
	defer t.mu.Unlock()
	s := TaskSnapshot{
		ID:       t.id,
		Type:     t.typ,
		Title:    t.title,
		Status:   t.status,
		Progress: t.progress,
		Error:    t.err,
	}
	if t.startedAt != nil {
		v := *t.startedAt
		s.StartedAt = &v
	}
	if t.endedAt != nil {
		v := *t.endedAt
		s.EndedAt = &v
	}
	return s
}

func (t *Task) markRunning(now time.Time) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.isTerminalLocked() {
		return
	}
	t.status = StatusRunning
	t.startedAt = &now
}

func (t *Task) finish(err error, now time.Time) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.endedAt = &now
	switch {
	case t.ctx != nil && t.ctx.Err() != nil:
		t.status = StatusCancelled
	case err != nil:
		t.status = StatusFailed
		t.err = err.Error()
	default:
		t.status = StatusCompleted
		t.progress = 1
	}
}

func (t *Task) cancelIfActive() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.isTerminalLocked() {
		return false
	}
	if t.cancel != nil {
		t.cancel()
	}
	return true
}

func (t *Task) terminal() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.isTerminalLocked()
}

func (t *Task) isTerminalLocked() bool {
	return t.status == StatusCompleted || t.status == StatusFailed || t.status == StatusCancelled
}

type Manager struct {
	db         *storage.DB
	mu         sync.Mutex
	tasks      map[string]*Task
	order      []string
	active     int
	maxTracked int
	maxPending int
	sem        chan struct{}
	wg         sync.WaitGroup
	closed     bool
}

func NewManager(maxConc int, db ...*storage.DB) *Manager {
	if maxConc < 1 {
		maxConc = 1
	}
	m := &Manager{
		tasks:      map[string]*Task{},
		maxTracked: defaultMaxTracked,
		maxPending: defaultMaxPending,
		sem:        make(chan struct{}, maxConc),
	}
	if len(db) > 0 {
		m.db = db[0]
	}
	return m
}

func (m *Manager) Submit(typ, title string, fn func(context.Context, *Task) error) (string, error) {
	if fn == nil {
		return "", fmt.Errorf("task function is nil")
	}

	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return "", fmt.Errorf("manager is closed")
	}
	if m.active >= m.maxPending {
		m.mu.Unlock()
		return "", fmt.Errorf("queue is full")
	}
	m.pruneLocked()
	if len(m.tasks) >= m.maxTracked {
		m.mu.Unlock()
		return "", fmt.Errorf("queue is full")
	}

	id := uuid.NewString()
	ctx, cancel := context.WithCancel(context.Background())
	t := &Task{
		id:     id,
		typ:    typ,
		title:  title,
		status: StatusPending,
		cancel: cancel,
		ctx:    ctx,
		fn:     fn,
	}
	m.tasks[id] = t
	m.order = append(m.order, id)
	m.active++
	m.wg.Add(1)
	m.mu.Unlock()

	m.persist(t.Snapshot())
	go m.run(t)
	return id, nil
}

func (m *Manager) run(t *Task) {
	defer m.wg.Done()
	m.sem <- struct{}{}
	defer func() { <-m.sem }()

	t.markRunning(time.Now())
	m.persist(t.Snapshot())

	var err error
	func() {
		defer func() {
			if r := recover(); r != nil {
				err = fmt.Errorf("panic: %v\n%s", r, debug.Stack())
			}
		}()
		err = t.fn(t.ctx, t)
	}()

	t.finish(err, time.Now())
	m.persist(t.Snapshot())

	m.mu.Lock()
	m.active--
	m.pruneLocked()
	m.mu.Unlock()
}

func (m *Manager) Shutdown(timeout time.Duration) bool {
	m.mu.Lock()
	m.closed = true
	for _, t := range m.tasks {
		t.cancelIfActive()
	}
	m.mu.Unlock()

	done := make(chan struct{})
	go func() {
		m.wg.Wait()
		close(done)
	}()
	if timeout <= 0 {
		<-done
		return true
	}
	select {
	case <-done:
		return true
	case <-time.After(timeout):
		return false
	}
}

func (m *Manager) Get(id string) (TaskSnapshot, bool) {
	m.mu.Lock()
	t, ok := m.tasks[id]
	m.mu.Unlock()
	if !ok {
		return TaskSnapshot{}, false
	}
	return t.Snapshot(), true
}

func (m *Manager) Cancel(id string) bool {
	m.mu.Lock()
	t, ok := m.tasks[id]
	m.mu.Unlock()
	if !ok {
		return false
	}
	return t.cancelIfActive()
}

func (m *Manager) List() []TaskSnapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]TaskSnapshot, 0, len(m.order))
	for _, id := range m.order {
		t := m.tasks[id]
		if t != nil {
			out = append(out, t.Snapshot())
		}
	}
	return out
}

func (m *Manager) pruneLocked() {
	if len(m.tasks) < m.maxTracked {
		return
	}
	kept := m.order[:0]
	for _, id := range m.order {
		t := m.tasks[id]
		if t != nil && t.terminal() {
			delete(m.tasks, id)
			continue
		}
		kept = append(kept, id)
	}
	m.order = kept
}

func (m *Manager) persist(s TaskSnapshot) {
	if m.db == nil {
		return
	}
	_ = m.db.UpsertOperation(&storage.Operation{
		ID:        s.ID,
		Type:      s.Type,
		Status:    string(s.Status),
		Title:     s.Title,
		Progress:  s.Progress,
		StartedAt: s.StartedAt,
		EndedAt:   s.EndedAt,
		Error:     s.Error,
	})
}

package operations

import (
	"context"
	"testing"
	"time"
)

func TestManager(t *testing.T) {
	m := NewManager(2)
	id := m.Submit("test", "t", func(ctx context.Context, task *Task) error {
		time.Sleep(50 * time.Millisecond)
		return nil
	})
	time.Sleep(10 * time.Millisecond)
	task, ok := m.Get(id)
	if !ok || task.Status != StatusRunning && task.Status != StatusPending {
		t.Fatalf("status %s", task.Status)
	}
	// wait completion
	time.Sleep(100 * time.Millisecond)
	task, _ = m.Get(id)
	if task.Status != StatusCompleted {
		t.Fatalf("status %s", task.Status)
	}
	// cancel
	id2 := m.Submit("test", "t2", func(ctx context.Context, task *Task) error {
		<-ctx.Done()
		return ctx.Err()
	})
	m.Cancel(id2)
	time.Sleep(50 * time.Millisecond)
	task2, _ := m.Get(id2)
	if task2.Status != StatusCancelled {
		t.Fatalf("status %s", task2.Status)
	}
}

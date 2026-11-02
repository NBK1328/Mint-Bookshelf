package device

import "testing"

func TestTransferProgressAndCancel(t *testing.T) {
	s := &Session{}
	s.beginTransfer()
	sent, total, active := s.TransferProgress()
	if !active || sent != 0 || total != 0 {
		t.Fatalf("initial progress = %d/%d active=%v", sent, total, active)
	}
	if s.reportProgress(10, 100) {
		t.Fatal("unexpected cancel")
	}
	s.CancelTransfer()
	if !s.reportProgress(20, 100) {
		t.Fatal("cancel was not propagated")
	}
	sent, total, active = s.TransferProgress()
	if !active || sent != 20 || total != 100 {
		t.Fatalf("progress = %d/%d active=%v", sent, total, active)
	}
	s.endTransfer()
	if _, _, active := s.TransferProgress(); active {
		t.Fatal("transfer still active")
	}
}

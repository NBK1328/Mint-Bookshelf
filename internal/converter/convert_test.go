package converter

import (
	"context"
	"os"
	"testing"
)

func TestConvert(t *testing.T) {
	c, err := DetectCalibre()
	if err != nil {
		t.Skip(err)
	}
	in := "/tmp/cvtest.txt"
	os.WriteFile(in, []byte("Hello. Chapter one."), 0o644)
	out := "/tmp/cvtest.azw3"
	os.Remove(out)
	err = c.Convert(context.Background(), Options{Input: in, Output: out, ToFormat: "azw3"}, func(s string) {})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(out); err != nil {
		t.Fatal(err)
	}
	t.Log("converted", out)
}

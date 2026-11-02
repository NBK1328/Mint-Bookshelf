package converter

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

type Calibre struct {
	Path    string // path to ebook-convert
	Version string
}

func DetectCalibre() (*Calibre, error) {
	candidates := []string{}
	if p := os.Getenv("KINDLE_MANAGER_CALIBRE"); p != "" {
		candidates = append(candidates, p)
	}
	// common
	for _, name := range []string{"ebook-convert"} {
		if p, err := exec.LookPath(name); err == nil {
			candidates = append(candidates, p)
		}
	}
	// macOS app bundle
	if runtime.GOOS == "darwin" {
		candidates = append(candidates, "/Applications/calibre.app/Contents/MacOS/ebook-convert")
	}
	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && !info.IsDir() {
			cal := &Calibre{Path: c}
			ver, _ := cal.VersionString(context.Background())
			cal.Version = ver
			return cal, nil
		}
	}
	slog.Warn("calibre not found")
	return nil, fmt.Errorf("ebook-convert not found")
}

func (c *Calibre) VersionString(ctx context.Context) (string, error) {
	cmd := exec.CommandContext(ctx, c.Path, "--version")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func (c *Calibre) ArchOK() bool {
	// check file output contains arm64
	out, err := exec.Command("file", c.Path).Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), "arm64")
}

type Options struct {
	Input     string
	Output    string
	ToFormat  string
	FontSize  int
	ExtraArgs []string
}

func (c *Calibre) Convert(ctx context.Context, opts Options, onProgress func(line string)) error {
	if c == nil || c.Path == "" {
		return fmt.Errorf("calibre not available")
	}
	outPath := opts.Output
	if outPath == "" {
		dir := filepath.Dir(opts.Input)
		base := strings.TrimSuffix(filepath.Base(opts.Input), filepath.Ext(opts.Input))
		outPath = filepath.Join(dir, base+"."+opts.ToFormat)
	}
	args := []string{opts.Input, outPath}
	if opts.FontSize > 0 {
		args = append(args, "--base-font-size", fmt.Sprintf("%d", opts.FontSize))
	}
	args = append(args, opts.ExtraArgs...)
	cmd := exec.CommandContext(ctx, c.Path, args...)
	// capture stdout/stderr
	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := stdout.Read(buf)
			if n > 0 && onProgress != nil {
				onProgress(string(buf[:n]))
			}
			if err != nil {
				break
			}
		}
	}()
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := stderr.Read(buf)
			if n > 0 && onProgress != nil {
				onProgress(string(buf[:n]))
			}
			if err != nil {
				break
			}
		}
	}()
	return cmd.Wait()
}

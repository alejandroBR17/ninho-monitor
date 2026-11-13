//go:build !windows

package main

import (
	"context"
	"os"
	"os/exec"
)

func protect(b []byte) ([]byte, error)   { return b, nil }
func unprotect(b []byte) ([]byte, error) { return b, nil }
func replaceFile(a, b string) error      { return os.Rename(a, b) }
func attachProcess(cmd *exec.Cmd) error  { return nil }
func keepAwake(ctx context.Context)      {}
func openBrowser(url string)             {}

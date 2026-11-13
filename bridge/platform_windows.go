//go:build windows

package main

import (
	"context"
	"os"
	"os/exec"
	"runtime"
	"sync"
	"syscall"
	"unsafe"
)

var crypt = syscall.NewLazyDLL("crypt32.dll")
var kernel = syscall.NewLazyDLL("kernel32.dll")

type blob struct {
	Size uint32
	Data *byte
}

func protect(data []byte) ([]byte, error)   { return cryptData(data, true) }
func unprotect(data []byte) ([]byte, error) { return cryptData(data, false) }
func cryptData(data []byte, encrypt bool) ([]byte, error) {
	var in blob
	if len(data) > 0 {
		in = blob{uint32(len(data)), &data[0]}
	}
	var out blob
	name := "CryptUnprotectData"
	if encrypt {
		name = "CryptProtectData"
	}
	r, _, e := crypt.NewProc(name).Call(uintptr(unsafe.Pointer(&in)), 0, 0, 0, 0, 1, uintptr(unsafe.Pointer(&out)))
	if r == 0 {
		return nil, e
	}
	defer kernel.NewProc("LocalFree").Call(uintptr(unsafe.Pointer(out.Data)))
	return append([]byte(nil), unsafe.Slice(out.Data, int(out.Size))...), nil
}
func replaceFile(a, b string) error {
	aa, _ := syscall.UTF16PtrFromString(a)
	bb, _ := syscall.UTF16PtrFromString(b)
	r, _, e := kernel.NewProc("MoveFileExW").Call(uintptr(unsafe.Pointer(aa)), uintptr(unsafe.Pointer(bb)), 1|8)
	if r == 0 {
		return e
	}
	return nil
}

type basicLimit struct {
	User, Job            int64
	Flags                uint32
	Min, Max             uintptr
	Active               uint32
	Affinity             uintptr
	Priority, Scheduling uint32
}
type extendedLimit struct {
	Basic                                          basicLimit
	IO                                             [6]uint64
	ProcessMemory, JobMemory, PeakProcess, PeakJob uintptr
}

var job uintptr
var jobOnce sync.Once
var jobError error

func attachProcess(cmd *exec.Cmd) error {
	jobOnce.Do(func() {
		h, _, e := kernel.NewProc("CreateJobObjectW").Call(0, 0)
		if h == 0 {
			jobError = e
			return
		}
		info := extendedLimit{}
		info.Basic.Flags = 0x2000
		r, _, e := kernel.NewProc("SetInformationJobObject").Call(h, 9, uintptr(unsafe.Pointer(&info)), unsafe.Sizeof(info))
		if r == 0 {
			jobError = e
			return
		}
		job = h
	})
	if jobError != nil {
		return jobError
	}
	h, e := syscall.OpenProcess(0x0100|0x0001, false, uint32(cmd.Process.Pid))
	if e != nil {
		return e
	}
	defer syscall.CloseHandle(h)
	r, _, e := kernel.NewProc("AssignProcessToJobObject").Call(job, uintptr(h))
	if r == 0 {
		return e
	}
	return nil
}
func keepAwake(ctx context.Context) {
	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		kernel.NewProc("SetThreadExecutionState").Call(0x80000001)
		<-ctx.Done()
		kernel.NewProc("SetThreadExecutionState").Call(0x80000000)
	}()
}
func openBrowser(url string) {
	_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
}

var _ = os.ErrNotExist

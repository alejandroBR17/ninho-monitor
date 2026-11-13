//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

type systemPowerStatus struct {
	AC           byte
	BatteryFlag  byte
	Percent      byte
	Reserved     byte
	LifeTime     uint32
	FullLifeTime uint32
}

func readNotebookHealth(root string) powerReading {
	p := powerReading{AC: -1, Percent: -1}
	var status systemPowerStatus
	ok, _, _ := kernel.NewProc("GetSystemPowerStatus").Call(uintptr(unsafe.Pointer(&status)))
	if ok != 0 {
		p.Known = true
		if status.AC <= 1 {
			p.AC = int(status.AC)
		}
		p.HasBattery = status.BatteryFlag != 255 && status.BatteryFlag&128 == 0
		p.Charging = status.BatteryFlag != 255 && status.BatteryFlag&8 != 0
		if status.Percent <= 100 && p.HasBattery {
			p.Percent = int(status.Percent)
		}
	}
	path, e := syscall.UTF16PtrFromString(root)
	if e == nil {
		var free, total, totalFree uint64
		ok, _, _ = kernel.NewProc("GetDiskFreeSpaceExW").Call(uintptr(unsafe.Pointer(path)), uintptr(unsafe.Pointer(&free)), uintptr(unsafe.Pointer(&total)), uintptr(unsafe.Pointer(&totalFree)))
		if ok != 0 {
			p.DiskKnown = true
			p.DiskFree = free
		}
	}
	return p
}

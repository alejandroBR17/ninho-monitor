//go:build !windows

package main

// Development platforms must not invent a healthy Windows battery reading.
func readNotebookHealth(root string) powerReading { return powerReading{AC: -1, Percent: -1} }

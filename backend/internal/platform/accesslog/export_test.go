package accesslog

import "time"

// SetRecordTimeout shortens the write bound for a test and restores it after.
func SetRecordTimeout(d time.Duration) (restore func()) {
	old := recordTimeout
	recordTimeout = d
	return func() { recordTimeout = old }
}

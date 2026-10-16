package photoutil

// SetTakenDatesPerList caps the capture dates one listing reads, for a test,
// and returns the restore.
func SetTakenDatesPerList(n int) (restore func()) {
	was := takenDatesPerList
	takenDatesPerList = n
	return func() { takenDatesPerList = was }
}

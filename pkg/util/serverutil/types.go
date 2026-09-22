package serverutil

import (
	"io"
	"strings"
)

// redactingWriter passes log output through with every space-separated field
// run through redactQuery, so a URL anywhere in a line, such as the request
// line of a dump, loses its credentials.
type redactingWriter struct {
	out io.Writer
}

func (w redactingWriter) Write(p []byte) (int, error) {
	fields := strings.Split(string(p), " ")
	for i, field := range fields {
		fields[i] = redactQuery(field)
	}
	if _, err := io.WriteString(w.out, strings.Join(fields, " ")); err != nil {
		return 0, err
	}
	return len(p), nil
}

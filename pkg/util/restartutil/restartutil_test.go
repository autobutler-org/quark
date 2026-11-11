package restartutil

import (
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// Tests never run as the installed service, so SupervisedEnv decides.
func TestGetStatus(t *testing.T) {
	cases := []struct {
		value string
		want  Reason
	}{
		{"1", ReasonNone},
		{"true", ReasonNone},
		{"", ReasonNotSupervised},
		{"0", ReasonNotSupervised},
		{"yes", ReasonNotSupervised},
	}
	for _, tc := range cases {
		t.Run(tc.value, func(t *testing.T) {
			t.Setenv(SupervisedEnv, tc.value)
			got, err := GetStatus(GetStatusParams{})
			if err != nil {
				t.Fatal(err)
			}
			if got.Reason != tc.want || got.Available != (tc.want == ReasonNone) {
				t.Errorf("GetStatus = %+v, want reason %q", got, tc.want)
			}
		})
	}
}

func TestRestart(t *testing.T) {
	exits := make(chan int, 2)
	t.Cleanup(updateutil.SetRestartExitForTest(func(code int) { exits <- code }))

	t.Setenv(SupervisedEnv, "")
	if _, err := Restart(RestartParams{}); !errors.Is(err, ErrUnsupervised) {
		t.Fatalf("unsupervised Restart err = %v, want ErrUnsupervised", err)
	}

	t.Setenv(SupervisedEnv, "1")
	if _, err := Restart(RestartParams{}); err != nil {
		t.Fatal(err)
	}
	if _, err := Restart(RestartParams{}); !errors.Is(err, updateutil.ErrUpdateInProgress) {
		t.Fatalf("second Restart err = %v, want ErrUpdateInProgress", err)
	}
	if code := <-exits; code != 0 {
		t.Errorf("exit code = %d, want 0", code)
	}
	if len(exits) != 0 {
		t.Error("a refused restart exited")
	}
}

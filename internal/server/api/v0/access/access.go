package v0_access

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

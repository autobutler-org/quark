package storageutil_test

import (
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/stretchr/testify/assert"
)

func TestIsTrashPath(t *testing.T) {
	assert.True(t, storageutil.IsTrashPath(".trash"))
	assert.True(t, storageutil.IsTrashPath(".trash/x"))
	assert.True(t, storageutil.IsTrashPath("./.trash/x/"))
	assert.False(t, storageutil.IsTrashPath(".trashy"))
	assert.False(t, storageutil.IsTrashPath("docs/.trash"))
}

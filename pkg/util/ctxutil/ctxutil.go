// Package ctxutil stores and fetches typed values on a gin context. It is how a handler gets the dependency graph:
// ctxutil.Get[deputil.Dependencies](c, "deps").
package ctxutil

import "github.com/gin-gonic/gin"

func With[T any](ctx *gin.Context, key string, value T) *gin.Context {
	ctx.Set(key, value)
	return ctx
}

func Get[T any](ctx *gin.Context, key string) (T, bool) {
	var obj T
	val, exists := ctx.Get(key)
	if !exists {
		return obj, false
	}
	typedObj, ok := val.(T)
	if !ok {
		return obj, false
	}
	return typedObj, true
}

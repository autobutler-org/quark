package v0_chat

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// requestContext is what every chat handler reads first: the dependencies,
// who the request acts as, and the channel id in the URL when there is one.
func requestContext(c *gin.Context) (deputil.Dependencies, accessutil.Principal, *serverutil.Response) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return deps, accessutil.Principal{}, serverutil.InternalServerError(nil)
	}
	if deps.Database() == nil {
		return deps, accessutil.Principal{}, serverutil.InternalServerError(errors.New("database unavailable"))
	}
	principal, _ := ctxutil.Get[accessutil.Principal](c, "principal")
	return deps, principal, nil
}

// callerContext is requestContext for a route that acts on the caller's own
// account, which needs one.
func callerContext(c *gin.Context) (deputil.Dependencies, accessutil.Principal, *serverutil.Response) {
	deps, principal, failed := requestContext(c)
	if failed == nil && principal.UserID == 0 {
		failed = serverutil.Unauthorized(errors.New("not authenticated"))
	}
	return deps, principal, failed
}

// rateLimited is a 429 once the caller has spent its budget for route on
// the chat limiter, and nil otherwise (#2485). Each route has its own bucket.
func rateLimited(deps deputil.Dependencies, principal accessutil.Principal, route string) *serverutil.Response {
	if deps.ChatRateLimiter().Allow(strconv.FormatInt(principal.UserID, 10) + " " + route) {
		return nil
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusTooManyRequests).WithError(errTooManyRequests)
}

// bindPostMessage reads a post. The poll object, when set, rejects a field of
// the wrong type or one the Quark does not know, as chatutil.ErrMalformedPoll
// (#3944). The rest of the body keeps the usual decoding: an unknown field
// there is ignored, and any other malformed body is the decoder's error.
func bindPostMessage(r io.Reader, body *postMessageBody) error {
	dec := json.NewDecoder(r)
	var raw struct {
		Ciphertext      []byte          `json:"ciphertext"`
		KeyVersion      int64           `json:"keyVersion"`
		ClientMessageID string          `json:"clientMessageId"`
		Poll            json.RawMessage `json:"poll"`
	}
	if err := dec.Decode(&raw); err != nil {
		return err
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("more than one JSON value")
		}
		return err
	}
	body.Ciphertext = raw.Ciphertext
	body.KeyVersion = raw.KeyVersion
	body.ClientMessageID = raw.ClientMessageID
	pollJSON := bytes.TrimSpace(raw.Poll)
	if len(pollJSON) == 0 || bytes.Equal(pollJSON, []byte("null")) {
		return nil
	}
	pollDec := json.NewDecoder(bytes.NewReader(pollJSON))
	pollDec.DisallowUnknownFields()
	var poll chatutil.PollSettings
	if err := pollDec.Decode(&poll); err != nil {
		return chatutil.ErrMalformedPoll
	}
	body.Poll = &poll
	return nil
}

// channelID reads the :id path parameter. One that isn't a positive integer
// names no channel.
func channelID(c *gin.Context) (int64, *serverutil.Response) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return 0, serverutil.NotFound(chatutil.ErrChannelNotFound)
	}
	return id, nil
}

// messageID reads the :id path parameter of a message route. One that isn't
// a positive integer names no message.
func messageID(c *gin.Context) (int64, *serverutil.Response) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return 0, serverutil.NotFound(chatutil.ErrMessageNotFound)
	}
	return id, nil
}

// chatError maps an error from chatutil to its status code. The sentinels'
// text is written for the app to show, so it goes out unwrapped.
func chatError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, chatutil.ErrChannelNotFound), errors.Is(err, chatutil.ErrMemberNotFound),
		errors.Is(err, accessutil.ErrPrincipalNotFound), errors.Is(err, chatutil.ErrKeysNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, chatutil.ErrEventNotFound), errors.Is(err, chatutil.ErrMessageNotFound),
		errors.Is(err, chatutil.ErrReactionNotFound), errors.Is(err, chatutil.ErrGrantNotFound),
		errors.Is(err, chatutil.ErrNotPoll), errors.Is(err, chatutil.ErrAttachmentNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, chatutil.ErrForbidden), errors.Is(err, chatutil.ErrNotHeld),
		errors.Is(err, chatutil.ErrNotSubset), errors.Is(err, chatutil.ErrCreatorRow),
		errors.Is(err, chatutil.ErrNotHolder), errors.Is(err, chatutil.ErrAdminOnly),
		errors.Is(err, chatutil.ErrRegenerateForbidden),
		errors.Is(err, chatutil.ErrReadOnly), errors.Is(err, chatutil.ErrNotMessageAuthor),
		errors.Is(err, chatutil.ErrNoReactions), errors.Is(err, chatutil.ErrNotReactionAuthor),
		errors.Is(err, chatutil.ErrNoAnswers), errors.Is(err, chatutil.ErrNotPollAuthor),
		errors.Is(err, chatutil.ErrCannotAttach):
		return serverutil.Forbidden(err)
	case errors.Is(err, chatutil.ErrInvalidPerms), errors.Is(err, chatutil.ErrNoPerms):
		return serverutil.NewResponse().WithStatusCode(http.StatusUnprocessableEntity).WithError(err)
	case errors.Is(err, chatutil.ErrMessageTooLarge), errors.Is(err, chatutil.ErrAttachmentTooLarge):
		return serverutil.NewResponse().WithStatusCode(http.StatusRequestEntityTooLarge).WithError(err)
	case errors.Is(err, chatutil.ErrNameTaken), errors.Is(err, chatutil.ErrVersionConflict), errors.Is(err, chatutil.ErrRotationNotNeeded),
		errors.Is(err, chatutil.ErrEventSigned),
		errors.Is(err, chatutil.ErrMessageDeleted), errors.Is(err, chatutil.ErrTooManyReactions),
		errors.Is(err, chatutil.ErrDuplicateMessage),
		errors.Is(err, chatutil.ErrPollClosed), errors.Is(err, chatutil.ErrAlreadyAnswered),
		errors.Is(err, chatutil.ErrAttachmentExists):
		return serverutil.Conflict(err)
	case errors.Is(err, chatutil.ErrInvalidName), errors.Is(err, chatutil.ErrInvalidTopic),
		errors.Is(err, chatutil.ErrDefaultChannel), errors.Is(err, chatutil.ErrDefaultEveryone), errors.Is(err, chatutil.ErrLastOwner),
		errors.Is(err, accessutil.ErrGrantTarget),
		errors.Is(err, chatutil.ErrInvalidKeys), errors.Is(err, chatutil.ErrInvalidGrant), errors.Is(err, chatutil.ErrGrantSignature),
		errors.Is(err, chatutil.ErrInvalidMessage), errors.Is(err, chatutil.ErrInvalidReaction),
		errors.Is(err, chatutil.ErrInvalidClientMessageID), errors.Is(err, chatutil.ErrInvalidPollAnswer),
		errors.Is(err, chatutil.ErrMalformedPoll), errors.Is(err, chatutil.ErrPollClosesAt),
		errors.Is(err, chatutil.ErrInvalidAttachment):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}

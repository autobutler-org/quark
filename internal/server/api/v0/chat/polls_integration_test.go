package v0_chat_test

import (
	"encoding/json"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// pollBody is a poll post of 64 bytes of fill under key version 1 with the
// JSON settings given.
func pollBody(fill byte, settings string) string {
	return `{"keyVersion":1,"ciphertext":"` + b64(fill, 64) + `","poll":` + settings + `}`
}

// answerBody is a poll answer of the one size the Quark takes.
func answerBody(fill byte) string {
	return messageBody(fill, chatutil.PollAnswerCiphertextBytes, 1)
}

// pollPath is a poll message's route with suffix.
func pollPath(id int64, suffix string) string {
	return "/chat/messages/" + strconv.FormatInt(id, 10) + suffix
}

// drainPollEvents empties the bus and returns the chat_poll_answer_changed
// events it held, the chat_poll_answers_changed notes, and how many
// chat_poll_closed it held, each in order.
func (h harness) drainPollEvents() ([]eventbus.ChatPollAnswerChanged, []eventbus.ChatPollAnswersChanged, int) {
	var answers []eventbus.ChatPollAnswerChanged
	var notes []eventbus.ChatPollAnswersChanged
	closed := 0
	for _, evt := range h.drain() {
		switch evt.Kind {
		case eventbus.EventChatPollAnswerChanged:
			answers = append(answers, evt.Data.(eventbus.ChatPollAnswerChanged))
		case eventbus.EventChatPollAnswersChanged:
			notes = append(notes, evt.Data.(eventbus.ChatPollAnswersChanged))
		case eventbus.EventChatPollClosed:
			closed++
		}
	}
	return answers, notes, closed
}

// pollRoom has bob make a keyed channel where carol and dave are members, and
// returns its path.
func pollRoom(t *testing.T, h harness) string {
	t.Helper()
	_, room := roomWithKey(t, h)
	for _, who := range []string{"carol", "dave"} {
		h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users[who], member...), nil)
	}
	return room
}

// TestChatPolls_AnswerCloseTombstone answers a poll once, refuses a second
// answer, enforces read_messages and add_reactions, embeds the poll in a
// page, closes it by hand, and drops its answers with its tombstone.
func TestChatPolls_AnswerCloseTombstone(t *testing.T) {
	h := newHarness(t)
	room := pollRoom(t, h)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["dave"], "manage_members"), nil)
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob",
		pollBody('p', `{"allowChange":false,"anonymous":false,"resultsAfterClose":false}`), &poll)
	if poll.Poll == nil || poll.Poll.Closed || poll.Poll.AllowChange {
		t.Fatalf("posted poll = %+v", poll.Poll)
	}
	answer, answers, closePath := pollPath(poll.ID, "/answer"), pollPath(poll.ID, "/answers"), pollPath(poll.ID, "/close")
	h.drainPollEvents()

	var carols chatutil.PollAnswer
	h.expect(t, http.StatusOK, http.MethodPut, answer, "carol", answerBody('c'), &carols)
	if carols.UserID != h.users["carol"] || !carols.Mine || carols.MessageID != poll.ID || carols.CreatedAt.IsZero() {
		t.Errorf("stored = %+v", carols)
	}
	if heard, notes, _ := h.drainPollEvents(); len(heard) != 1 || len(notes) != 0 || len(heard[0].Audience) != 2 ||
		heard[0].Answer.(chatutil.PollAnswer).UserID != h.users["carol"] {
		t.Errorf("heard = %+v, notes = %+v", heard, notes)
	}
	h.expect(t, http.StatusConflict, http.MethodPut, answer, "carol", answerBody('c'), nil)

	// Validation: exactly one size, and a key version the channel has.
	h.expect(t, http.StatusBadRequest, http.MethodPut, answer, "bob", messageBody('b', chatutil.PollAnswerCiphertextBytes-1, 1), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, answer, "bob", messageBody('b', chatutil.PollAnswerCiphertextBytes, 2), nil)

	// Permissions: no read_messages is 404, read without add_reactions 403.
	for _, as := range []string{"admin", "dave"} {
		h.expect(t, http.StatusNotFound, http.MethodPut, answer, as, answerBody('x'), nil)
		h.expect(t, http.StatusNotFound, http.MethodGet, answers, as, "", nil)
		h.expect(t, http.StatusNotFound, http.MethodPost, closePath, as, "", nil)
	}
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	h.expect(t, http.StatusForbidden, http.MethodPut, answer, "carol", answerBody('c'), nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], member...), nil)

	// A message that isn't a poll.
	var plain chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob", messageBody('m', 64, 1), &plain)
	if plain.Poll != nil {
		t.Errorf("plain message has a poll: %+v", plain.Poll)
	}
	h.expect(t, http.StatusNotFound, http.MethodPut, pollPath(plain.ID, "/answer"), "carol", answerBody('c'), nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, pollPath(plain.ID, "/answers"), "carol", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodPost, pollPath(plain.ID, "/close"), "bob", "", nil)

	// The author sees who answered; a page embeds the poll and its answers.
	var seen chatutil.ListPollAnswersResult
	h.expect(t, http.StatusOK, http.MethodGet, answers, "bob", "", &seen)
	if len(seen.Answers) != 1 || seen.Answers[0].UserID != h.users["carol"] || seen.Answers[0].Mine {
		t.Errorf("bob sees %+v", seen.Answers)
	}
	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, room+"/messages?after=0", "carol", "", &page)
	if len(page.Messages) != 2 || page.Messages[0].Poll == nil || len(page.Messages[0].Poll.Answers) != 1 ||
		!page.Messages[0].Poll.Answers[0].Mine || page.Messages[1].Poll != nil {
		t.Errorf("page = %+v", page.Messages)
	}

	// Closing by hand: the author alone, once, and then no answers.
	h.drainPollEvents()
	h.expect(t, http.StatusForbidden, http.MethodPost, closePath, "carol", "", nil)
	var closed chatutil.Poll
	h.expect(t, http.StatusOK, http.MethodPost, closePath, "bob", "", &closed)
	if !closed.Closed || closed.ClosedAt == nil {
		t.Errorf("closed = %+v", closed)
	}
	h.expect(t, http.StatusOK, http.MethodPost, closePath, "bob", "", nil)
	if _, _, n := h.drainPollEvents(); n != 1 {
		t.Errorf("chat_poll_closed heard %d times, want 1", n)
	}
	h.expect(t, http.StatusConflict, http.MethodPut, answer, "bob", answerBody('b'), nil)

	// The tombstone takes the poll and its answers.
	h.expect(t, http.StatusOK, http.MethodDelete, pollPath(poll.ID, ""), "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, answers, "bob", "", nil)
	var left int
	if err := h.deps.Database().Db.QueryRow(`SELECT (SELECT COUNT(*) FROM chat_poll_answers) + (SELECT COUNT(*) FROM chat_polls)`).Scan(&left); err != nil {
		t.Fatal(err)
	}
	if left != 0 {
		t.Errorf("%d poll rows outlived the tombstone", left)
	}
}

// TestChatPolls_ClosesByTime refuses an answer once closesAt has passed,
// with nothing having run at that time.
func TestChatPolls_ClosesByTime(t *testing.T) {
	h := newHarness(t)
	room := pollRoom(t, h)
	past := time.Now().Add(-time.Minute).UTC().Format(time.RFC3339)
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob",
		pollBody('p', `{"closesAt":"`+past+`","allowChange":true,"anonymous":false,"resultsAfterClose":false}`), &poll)
	if poll.Poll == nil || !poll.Poll.Closed || poll.Poll.ClosesAt == nil || poll.Poll.ClosedAt != nil {
		t.Fatalf("posted poll = %+v", poll.Poll)
	}
	h.expect(t, http.StatusConflict, http.MethodPut, pollPath(poll.ID, "/answer"), "carol", answerBody('c'), nil)
}

// TestChatPolls_AllowChangeReplaces keeps one answer per account when a poll
// lets an answer change.
func TestChatPolls_AllowChangeReplaces(t *testing.T) {
	h := newHarness(t)
	room := pollRoom(t, h)
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob",
		pollBody('p', `{"allowChange":true,"anonymous":false,"resultsAfterClose":false}`), &poll)
	var first, second chatutil.PollAnswer
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "carol", answerBody('1'), &first)
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "carol", answerBody('2'), &second)
	var seen chatutil.ListPollAnswersResult
	h.expect(t, http.StatusOK, http.MethodGet, pollPath(poll.ID, "/answers"), "bob", "", &seen)
	if second.ID != first.ID || len(seen.Answers) != 1 || seen.Answers[0].Ciphertext[0] != '2' {
		t.Errorf("first %d, second %d, seen %+v", first.ID, second.ID, seen.Answers)
	}
}

// TestChatPolls_AnonymousHidesUserIDs serves an anonymous poll's answers with
// no userId to anyone, its author included, and marks the caller's own.
func TestChatPolls_AnonymousHidesUserIDs(t *testing.T) {
	h := newHarness(t)
	room := pollRoom(t, h)
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob",
		pollBody('p', `{"allowChange":false,"anonymous":true,"resultsAfterClose":false}`), &poll)
	h.drainPollEvents()
	for _, as := range []string{"carol", "dave"} {
		if code, body := h.do(t, http.MethodPut, pollPath(poll.ID, "/answer"), as, answerBody('a')); code != http.StatusOK || strings.Contains(body, "userId") || strings.Contains(body, "createdAt") {
			t.Errorf("%s answering = %d %s", as, code, body)
		}
	}
	heard, notes, _ := h.drainPollEvents()
	if len(heard) != 0 || len(notes) != 2 {
		t.Errorf("heard %d per-answer events and %d notes, want 0 and 2", len(heard), len(notes))
	}
	for _, note := range notes {
		raw, err := json.Marshal(note)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(raw), "userId") || strings.Contains(string(raw), "answer") || strings.Contains(string(raw), "createdAt") || len(note.Audience) != 3 {
			t.Errorf("note = %s audience %v", raw, note.Audience)
		}
	}
	for _, as := range []string{"bob", "carol"} {
		code, body := h.do(t, http.MethodGet, pollPath(poll.ID, "/answers"), as, "")
		if code != http.StatusOK || strings.Contains(body, "userId") || strings.Contains(body, "createdAt") || strings.Contains(body, "updatedAt") || strings.Count(body, `"id"`) != 2 {
			t.Errorf("%s listing = %d %s", as, code, body)
		}
		code, body = h.do(t, http.MethodGet, room+"/messages?after=0", as, "")
		if code != http.StatusOK || strings.Count(body, "userId") != 0 {
			t.Errorf("%s page = %d %s", as, code, body)
		}
	}
	var carols chatutil.ListPollAnswersResult
	h.expect(t, http.StatusOK, http.MethodGet, pollPath(poll.ID, "/answers"), "carol", "", &carols)
	if mine := slices.IndexFunc(carols.Answers, func(a chatutil.PollAnswer) bool { return a.Mine }); mine < 0 ||
		slices.ContainsFunc(carols.Answers[mine+1:], func(a chatutil.PollAnswer) bool { return a.Mine }) {
		t.Errorf("carol's own isn't marked once: %+v", carols.Answers)
	}
}

// TestChatPolls_ResultsAfterClose shows a non-author only their own answer,
// in listings, pages and events, until the poll closes.
func TestChatPolls_ResultsAfterClose(t *testing.T) {
	h := newHarness(t)
	room := pollRoom(t, h)
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob",
		pollBody('p', `{"allowChange":false,"anonymous":false,"resultsAfterClose":true}`), &poll)
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "carol", answerBody('c'), nil)
	h.drainPollEvents()
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "dave", answerBody('d'), nil)
	heard, notes, _ := h.drainPollEvents()
	if len(notes) != 0 {
		t.Errorf("named poll sent %d anonymous notes", len(notes))
	}
	if len(heard) != 1 || len(heard[0].Audience) != 2 ||
		!slices.Contains(heard[0].Audience, h.users["bob"]) || !slices.Contains(heard[0].Audience, h.users["dave"]) {
		t.Errorf("dave's answer heard by %+v, want bob and dave", heard)
	}

	count := func(as string) (int, int) {
		var seen chatutil.ListPollAnswersResult
		h.expect(t, http.StatusOK, http.MethodGet, pollPath(poll.ID, "/answers"), as, "", &seen)
		var page chatutil.ListMessagesResult
		h.expect(t, http.StatusOK, http.MethodGet, room+"/messages?after=0", as, "", &page)
		return len(seen.Answers), len(page.Messages[0].Poll.Answers)
	}
	for as, want := range map[string]int{"bob": 2, "carol": 1, "dave": 1} {
		if listed, paged := count(as); listed != want || paged != want {
			t.Errorf("%s sees %d listed, %d paged while open, want %d", as, listed, paged, want)
		}
	}
	h.expect(t, http.StatusOK, http.MethodPost, pollPath(poll.ID, "/close"), "bob", "", nil)
	if listed, paged := count("carol"); listed != 2 || paged != 2 {
		t.Errorf("carol sees %d listed, %d paged once closed, want 2", listed, paged)
	}
}

// TestChatPolls_AnonymousHidesArrival serves an anonymous poll's answers with
// no timestamps and in ciphertext order, under an id that is not the row id
// and that stays put when the answer changes (#3943).
func TestChatPolls_AnonymousHidesArrival(t *testing.T) {
	h := newHarness(t)
	room := pollRoom(t, h)
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob",
		pollBody('p', `{"allowChange":true,"anonymous":true,"resultsAfterClose":false}`), &poll)
	h.drainPollEvents()

	var carols chatutil.PollAnswer
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "carol", answerBody('c'), &carols)
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "dave", answerBody('a'), nil)
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "bob", answerBody('b'), nil)

	code, body := h.do(t, http.MethodGet, pollPath(poll.ID, "/answers"), "bob", "")
	if code != http.StatusOK || strings.Contains(body, "createdAt") || strings.Contains(body, "updatedAt") || strings.Contains(body, "userId") {
		t.Fatalf("listing = %d %s", code, body)
	}
	var seen chatutil.ListPollAnswersResult
	if err := json.Unmarshal([]byte(body), &seen); err != nil {
		t.Fatal(err)
	}
	if got := answerFills(seen.Answers); got != "abc" {
		t.Fatalf("order = %q, want ciphertext order abc, not insertion c, a, b", got)
	}
	for _, answer := range seen.Answers {
		if !answer.CreatedAt.IsZero() || !answer.UpdatedAt.IsZero() || answer.UserID != 0 {
			t.Errorf("answer = %+v", answer)
		}
	}
	rowIDs := pollAnswerRowIDs(t, h, poll.ID)
	for _, answer := range seen.Answers {
		if slices.Contains(rowIDs, answer.ID) {
			t.Errorf("served id %d is a row id %v", answer.ID, rowIDs)
		}
	}
	carolsListed := seen.Answers[2]
	if carolsListed.ID != carols.ID || carolsListed.Ciphertext[0] != 'c' {
		t.Errorf("carol's list id %d != stored %d", carolsListed.ID, carols.ID)
	}

	var changed chatutil.PollAnswer
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "carol", answerBody('d'), &changed)
	if changed.ID != carols.ID || !changed.CreatedAt.IsZero() {
		t.Errorf("changed = %+v, want id %d and no timestamp", changed, carols.ID)
	}
	var after chatutil.ListPollAnswersResult
	h.expect(t, http.StatusOK, http.MethodGet, pollPath(poll.ID, "/answers"), "dave", "", &after)
	if got := answerFills(after.Answers); got != "abd" {
		t.Fatalf("order after change = %q, want abd", got)
	}
	if after.Answers[2].ID != carols.ID {
		t.Errorf("carol's id became %d, want %d", after.Answers[2].ID, carols.ID)
	}

	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, room+"/messages?after=0", "bob", "", &page)
	if page.Messages[0].Poll == nil || answerFills(page.Messages[0].Poll.Answers) != "abd" {
		t.Fatalf("page answers = %+v", page.Messages[0].Poll)
	}
	for _, answer := range page.Messages[0].Poll.Answers {
		if !answer.CreatedAt.IsZero() || !answer.UpdatedAt.IsZero() {
			t.Errorf("page answer carries a timestamp: %+v", answer)
		}
	}
}

// TestChatPolls_AnonymousResultsAreBatched holds an anonymous
// results-after-close poll's note to its author until a clock boundary, and
// tells the person who answered at once, with no answer attached (#3943).
func TestChatPolls_AnonymousResultsAreBatched(t *testing.T) {
	window := chatutil.AnonymousResultsWindow
	chatutil.AnonymousResultsWindow = 400 * time.Millisecond
	t.Cleanup(func() { chatutil.AnonymousResultsWindow = window })

	h := newHarness(t)
	room := pollRoom(t, h)
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob",
		pollBody('p', `{"allowChange":false,"anonymous":true,"resultsAfterClose":true}`), &poll)
	h.drainPollEvents()

	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "carol", answerBody('c'), nil)
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "dave", answerBody('d'), nil)
	heard, notes, _ := h.drainPollEvents()
	if len(heard) != 0 || len(notes) != 2 {
		t.Fatalf("immediate = %d answers and %d notes, want the two answerers only", len(heard), len(notes))
	}
	for _, note := range notes {
		if len(note.Audience) != 1 || (note.Audience[0] != h.users["carol"] && note.Audience[0] != h.users["dave"]) {
			t.Errorf("immediate audience = %v", note.Audience)
		}
		raw, err := json.Marshal(eventbus.Event{Kind: eventbus.EventChatPollAnswersChanged, Data: note})
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(raw), `"answer"`) || strings.Contains(string(raw), "userId") || strings.Contains(string(raw), "createdAt") {
			t.Errorf("note JSON = %s", raw)
		}
	}

	time.Sleep(time.Second)
	heard, notes, _ = h.drainPollEvents()
	if len(heard) != 0 || len(notes) != 1 || len(notes[0].Audience) != 1 || notes[0].Audience[0] != h.users["bob"] {
		t.Fatalf("batched = %d answers and %+v, want one note to bob", len(heard), notes)
	}
}

// answerFills is the first byte of each answer's ciphertext, in list order.
func answerFills(answers []chatutil.PollAnswer) string {
	out := make([]byte, len(answers))
	for i, answer := range answers {
		out[i] = answer.Ciphertext[0]
	}
	return string(out)
}

// pollAnswerRowIDs is the stored row ids of a poll's answers.
func pollAnswerRowIDs(t *testing.T, h harness, messageID int64) []int64 {
	t.Helper()
	rows, err := h.deps.Database().Db.Query(`SELECT id FROM chat_poll_answers WHERE message_id = ?`, messageID)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return ids
}

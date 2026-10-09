# Calendar Journeys

Covers the Calendar page (`/calendar`): one household calendar, Personal, that every signed-in account sees and edits
(#1144). Views have their own URLs (`/calendar/day`, `/calendar/week`, `/calendar/month`, `/calendar/upcoming`) and
the date on show is the `date` query (`?date=2026-09-29`). A bare `/calendar` opens the view chosen in Settings,
Week until one is chosen (JN-CA-011). Reminders show inside the app only; phone alerts are #1145.

---

### JN-CA-001: Open the calendar

**Preconditions:** Logged in.

**Steps:**

1. Open the drawer.
2. Tap **Calendar**.

**Expected result:**

- The app navigates to `/calendar/week`, or to the view chosen in Settings, and **Calendar** is marked in the
  drawer.
- This week shows, today's date filled in the accent color, the timeline opened at 8 AM.
- On today, a line in the accent color marks the current time, with the time in the hour column.

**Notes:** Week is the default view (#2519). JN-CA-011 chooses another.

---

### JN-CA-002: Move between views and dates

**Preconditions:** On the Calendar page.

**Steps:**

1. Tap **Month** in the view switch (on a phone, the chip naming the view, then **Month**).
2. Tap the next arrow twice.
3. Tap a date in the grid.
4. Tap **Today**.

**Expected result:**

- Switching view keeps the date: Week of Sep 29 becomes September's month.
- The arrows step by the view: a month here, a week in Week, a day in Day.
- Tapping a date opens it in Day view.
- **Today** returns to today in the view on show.
- The address bar follows every step, so reloading or sharing the link shows the same view and date.

**Notes:** On a phone a horizontal swipe on Day, Week or Month steps the same way as the arrows.

---

### JN-CA-003: Create a timed event

**Preconditions:** On the Calendar page, in Day or Week view.

**Steps:**

1. Tap an empty hour (on desktop, hovering shows "New event at …").
2. Type a title.
3. Tap **Save**.

**Expected result:**

- A form opens: a bottom sheet on a phone, a dialog on a wider screen, with the start set to that hour and the end an
  hour later.
- After saving, the form closes and the event shows at that hour, in every signed-in account's calendar.
- The view does not move (#320): saving an event in another month leaves that month on screen.

**Notes:** **New event** in the top bar opens the same form at the next whole hour today, or 9 AM on the date on show.
**Save** stays off until the event has a title and ends after it starts.

---

### JN-CA-004: Create an all-day event

**Preconditions:** On the Calendar page, in Month view.

**Steps:**

1. Long-press a date (on desktop, hover it and press the **+** in its corner).
2. Type a title and tap **Save**.

**Expected result:**

- The form opens with **All day** on and that date as start and end.
- The event shows on its date as a filled bar, and in Week and Day in the all-day row above the timeline.
- An all-day event spanning several dates shows on each of them.

---

### JN-CA-005: Repeat an event

**Preconditions:** Creating or editing an event.

**Steps:**

1. Under **Repeat**, choose **Weekly**.
2. Save.

**Expected result:**

- Beneath the choice the form says when it repeats: "Every week on Thursday."
- The event shows on that weekday in every week of every view, at the same time of day on both sides of a daylight
  saving change.
- **Monthly** keeps the date and skips months without it; **Daily** repeats every date.

**Notes:** Editing a repeating event changes every repeat, and the form says so ("Changes apply to every repeat.").

---

### JN-CA-006: Edit and delete an event

**Preconditions:** An event exists.

**Steps:**

1. Tap the event.
2. Change its title and tap **Save**.
3. Tap it again, tap **Delete**, and confirm.

**Expected result:**

- The form opens as **Edit event** with the event's fields.
- The change shows once saved; after the delete the event is gone, every repeat of a repeating event included.

**Notes:** On a phone or tablet the calendar's targets are sized for a finger, 48dp (#2939), so two places open the
day first, where the event has room to be tapped: an event's line in Month on a tablet (a phone's Month shows dots, and
already does), and events in Week that overlap into lanes too narrow for a finger. With a mouse each opens its event
directly.

---

### JN-CA-007: Set a reminder and see it come due

**Preconditions:** Creating or editing a timed event starting within the week.

**Steps:**

1. Under **Remind me**, choose **15 min**.
2. Save, then wait until 15 minutes before the event.

**Expected result:**

- The form notes "Shows in Upcoming. Phone alerts coming later."
- In Upcoming the event shows a bell with "15 min before"; once due, "Starts in 15 min" in the warning color.
- Day, Week and Month show a reminder bar above the view, with **Open** and **Dismiss**.

**Notes:** An all-day event's reminder is at 9 AM, on the day or the day before (#2522 lets you choose the time).

---

### JN-CA-008: See the next seven days

**Preconditions:** On the Calendar page.

**Steps:**

1. Choose **Upcoming** in the view switch.

**Expected result:**

- The events from now to a week ahead are listed under **Today**, **Tomorrow** and each weekday.
- Timed events already over today are left out.
- With nothing coming up: "Nothing in the next 7 days" and an **Add an event** button.

---

### JN-CA-009: See only my events, or one person's

**Preconditions:** On the Calendar page. Events exist that were created by more than one account.

**Steps:**

1. Tap **My events** in the row above the calendar.
2. Switch view, and step forward a span.
3. As an admin, tap **Person** and choose another account.
4. Tap **Everyone**.

**Expected result:**

- **My events** shows only events this account created, in every view, in Upcoming and in the reminder bar. The
  address bar gains `mine=true`, which survives the step, the view switch, and a reload.
- An admin's person chip lists the Quark's active accounts; choosing one shows only that account's events and names
  them on the chip (`person=<name>` in the address bar).
- **Everyone** shows every event again.

**Notes:** This is a filter, not privacy: every account still sees and edits every event (#2544). Only admins get
the person chip, since only admins can list accounts. Events created before owners were recorded belong to nobody
and show only under **Everyone**.

---

### JN-CA-010: End a repeating event on a date

**Preconditions:** Creating or editing a repeating event.

**Steps:**

1. Under **Repeat ends**, choose **On a date**.
2. Tap the date and pick the last date it should repeat on.
3. Save.

**Expected result:**

- **Repeat ends** shows only while the event repeats, and starts on **Never**.
- **On a date** fills in the date a month after the first occurrence; the line beneath **Repeat** reads "Every week
  on Thursday until Oct 31, 2026."
- The event repeats up to and including that date and not after it, in every view; Upcoming reads "Weekly until
  Oct 31, 2026."
- A date before the event's first date says "The repeat can't end before the event starts." and Save waits.
- Choosing **Never** again makes it repeat forever.

**Notes:** The end date is a calendar date, the same wherever the calendar is read (#2524). The Quark leaves a series
that ended before the dates on screen out of what it sends (#2535). An event saved by an app from before end dates
repeats forever.

---

### JN-CA-011: Choose the view Calendar opens on

**Preconditions:** Logged in, on Settings' General tab.

**Steps:**

1. Under **Calendar opens on**, choose **Month**.
2. Open the drawer and tap **Calendar**.

**Expected result:**

- The dropdown lists **Day**, **Week**, **Month** and **Upcoming**, and starts on **Week**.
- The app navigates to `/calendar/month`, and opens there every time after, across restarts.
- A link that names a view still wins: `/calendar/day` opens Day.
- Switching views on the Calendar page does not change the choice.

**Notes:** The choice is kept on this device, not on the Quark: another phone or browser has its own (#2521). The
control is hidden while the calendar is turned off for this Quark (#2609).

---

### JN-CA-012: Drag an event to a new time or length

**Preconditions:** A timed event exists, and Day or Week is on show.

**Steps:**

1. With a mouse, drag the event up or down, or in Week across to another day, and let go.
2. Drag its bottom edge down and let go.
3. On a phone or tablet, hold the event first, then drag; hold its bottom edge to drag its end.
4. With a keyboard, focus the event and press **Alt** with an arrow; hold **Shift** too to move its end.

**Expected result:**

- The event moves in 15-minute steps, and a preview shows the times it would land on until it is let go.
- Dragging the event keeps its length; dragging its bottom edge moves its end alone, and never past its start.
- **Alt+Up** and **Alt+Down** move it 15 minutes, **Alt+Left** and **Alt+Right** a day in Week, and
  **Alt+Shift+Up** and **Alt+Shift+Down** move its end. The focus stays on the event.
- The event shows at its new time at once and stays there once saved. If the save fails, a message says so and the
  event goes back.
- A repeating event moves as a whole series: every repeat shifts by as much, as it does from the form (JN-CA-006).

**Notes:** A move stays on the dates on show and keeps the start on its own day; the form reaches anywhere else
(#2526). On a phone a swipe over an event still scrolls the timeline, which is why a drag starts with a hold. The
timeline does not scroll under a drag. All-day events, and events in Week that overlap into lanes too narrow for a
finger, are not dragged: the form moves the first, and the Day view has room for the second.

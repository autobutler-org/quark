# Calendar Journeys

Covers the Calendar page (`/calendar`): one household calendar, Personal, that every signed-in account sees and edits
(#1144). Views have their own URLs (`/calendar/day`, `/calendar/week`, `/calendar/month`, `/calendar/upcoming`) and
the date on show is the `date` query (`?date=2026-09-29`). Reminders show inside the app only; phone alerts are
#1145.

---

### JN-CA-001: Open the calendar

**Preconditions:** Logged in.

**Steps:**

1. Open the drawer.
2. Tap **Calendar**.

**Expected result:**

- The app navigates to `/calendar/week`, and **Calendar** is marked in the drawer.
- This week shows, today's date filled in the accent color, the timeline opened at 8 AM.
- On today, a line in the accent color marks the current time, with the time in the hour column.

**Notes:** Week is the default view (#2519). Choosing another default is #2521.

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

**Notes:** The presets have no end date yet (#2524). Editing a repeating event changes every repeat, and the form
says so ("Changes apply to every repeat.").

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

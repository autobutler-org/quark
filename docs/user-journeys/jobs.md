# Jobs Journeys

Covers the System page's Jobs tab (`/system/jobs`): long-running work on the Quark, such as video conversions, with
Cancel and Retry.

---

### JN-JOB-001: View jobs

**Preconditions:** User is logged in. Quark is reachable.

**Steps:**

1. Open the navigation drawer and tap **System**.
2. Tap the **Jobs** tab.

**Expected result:**

- App navigates to `/system/jobs`.
- Jobs are listed newest first, each with its status and progress.
- With no jobs, an empty state is shown rather than a blank page.

**Notes:**

- The old `/jobs` address redirects here, with the query kept.

---

### JN-JOB-002: Cancel a running job

**Preconditions:** User is on `/system/jobs` with a job queued or running.

**Steps:**

1. Tap **Cancel** on the job.

**Expected result:**

- The job stops, and its row shows **Canceled**.
- If the Quark refuses, a snack bar says why and the job is left as it was.

---

### JN-JOB-003: Retry a failed job

**Preconditions:** User is on `/system/jobs` with a failed job.

**Steps:**

1. Tap **Retry** on the job.

**Expected result:**

- The job is queued again, and its row shows **Queued** or **Running**.
- If the Quark refuses, a snack bar says why.

---

### JN-JOB-004: Open jobs from the badge or a notice

**Preconditions:** User is logged in, on any page with a top bar.

**Steps:**

1. Start a video conversion, so a job is running.
2. Tap the running-jobs badge in the top bar.

**Expected result:**

- App navigates to `/system/jobs`.

**Notes:**

- The **View** action on the "Conversion started" snack bar, and on the snack bar a failed job raises, opens the same
  tab.

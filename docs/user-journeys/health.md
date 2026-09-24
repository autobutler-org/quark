# Health Journeys

Covers the System page's Health tab (`/system/health`) — system metrics and status for the quark device.

---

### JN-HE-001: View health dashboard

**Preconditions:** User is logged in. Quark is reachable.

**Steps:**

1. Navigate to `/system/health`.

**Expected result:**

- Health metrics are displayed: CPU usage, disk usage, memory, temperature, uptime, etc.
- Values are current (fetched on load).

**Notes:**

- **System** in the drawer opens `/system`, which lands on this tab. The old `/health` address redirects here.

---

### JN-HE-002: Auto-refresh health metrics

**Preconditions:** User is on `/system/health`.

**Steps:**

1. Wait 15 seconds (the configured auto-refresh interval).

**Expected result:**

- Metrics update automatically without a manual refresh.
- No visible flash or layout shift during refresh.

**Notes:**

- Only while this tab is on screen: on the Storage or Jobs tab, Health stops polling.

---

### JN-HE-003: Manually refresh health metrics

**Preconditions:** User is on `/system/health`.

**Steps:**

1. Tap the **Refresh** button in the app bar.

**Expected result:**

- Metrics refresh immediately.
- A loading indicator is shown during the fetch.

---

### JN-HE-004: Health page when quark is unreachable

**Preconditions:** Quark is offline or the host is misconfigured.

**Steps:**

1. Navigate to `/system/health`.

**Expected result:**

- An error message is shown explaining the quark cannot be reached.
- No crash or blank screen.

---

### JN-HE-005: Health page with no host configured

**Preconditions:** No host is configured in settings.

**Steps:**

1. Navigate to `/system/health`.

**Expected result:**

- Empty state or prompt to configure a host is shown.
- No error thrown.

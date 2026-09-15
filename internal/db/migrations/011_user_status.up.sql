-- Whether an account may sign in (#1908). A pending account is a request an
-- admin has not approved yet; a disabled one was turned off by an admin and
-- keeps everything it owns. Existing accounts are active.
ALTER TABLE users
ADD COLUMN status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('pending', 'active', 'disabled'));

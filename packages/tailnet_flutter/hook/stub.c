/* cspell:words stdlib strdup tsnetbridge */
/*
 * Stand-in for hosts that are not the iOS or Android app. The Dart side
 * never calls these there. They exist so a desktop build can link.
 * Kept out of cmd/tsnetbridge: cgo would otherwise link it beside the real
 * exports and fail with duplicate symbols.
 */
#include <stdlib.h>
#include <string.h>

int quark_tsnet_start(const char *state_dir, const char *control_url,
                      const char *auth_key, const char *hostname,
                      const char *upstream) {
  (void)state_dir;
  (void)control_url;
  (void)auth_key;
  (void)hostname;
  (void)upstream;
  return -1;
}

void quark_tsnet_stop(void) {}

char *quark_tsnet_status(void) {
  const char *s =
      "{\"state\":\"Stopped\",\"tailnetIPs\":[],\"port\":0,\"error\":\"\"}";
  return strdup(s);
}

char *quark_tsnet_token(void) { return strdup(""); }

void quark_tsnet_free(void *p) { free(p); }

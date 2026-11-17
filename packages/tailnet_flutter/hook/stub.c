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

char *quark_tsnet_peer_status(void) {
  const char *s = "{\"state\":\"Stopped\",\"quark\":null,\"network\":null,"
                  "\"pathChanges\":[],\"requests\":[]}";
  return strdup(s);
}

char *quark_tsnet_ping(int count) {
  (void)count;
  const char *s = "{\"tunnel\":null,\"tcp\":{\"sent\":0,\"received\":0,"
                  "\"minMs\":0,\"avgMs\":0,\"error\":\"no node\"}}";
  return strdup(s);
}

void quark_tsnet_free(void *p) { free(p); }

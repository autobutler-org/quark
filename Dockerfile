# Quark release image. Nothing is compiled here: the GoReleaser tarball for this image's own
# architecture is downloaded, checksum-verified and copied in. Build it with `make build/docker`;
# see docs/container.md for running it.

# Alpine is fine for fetching -- this stage only moves bytes around and none of its layers ship.
FROM alpine:3.24 AS fetch

# Bare semver, no leading "v": [major].[minor].[patch], not v[major].[minor].[patch]
ARG VERSION
# Set by buildx per manifest entry, so this works for a cross-build too.
ARG TARGETARCH
ARG BASE_URL=https://github.com/autobutler-org/quark/releases/download

RUN test -n "$VERSION" || { \
        echo "ERROR: the VERSION build arg is required (bare semver, e.g. 0.36.2)." >&2; \
        echo "  Run \`make build/docker\`, or pass --build-arg VERSION=<x.y.z>." >&2; \
        echo "  Released versions: https://github.com/autobutler-org/quark/releases" >&2; \
        exit 1; }; \
    case "$TARGETARCH" in amd64|arm64) ;; *) \
        echo "ERROR: no Quark release is published for '$TARGETARCH'." >&2; \
        echo "  Build for linux/amd64 or linux/arm64." >&2; \
        exit 1 ;; esac

WORKDIR /fetch
RUN wget -q "$BASE_URL/v$VERSION/quark_${VERSION}_checksums.txt"
RUN wget -q "$BASE_URL/v$VERSION/quark_Linux_$([ "$TARGETARCH" = amd64 ] && echo x86_64 || echo arm64).tar.gz"
# Narrowed to the one tarball we actually downloaded: busybox sha256sum has no
# --ignore-missing, so checking the whole file would fail on the arch we skipped. The empty check
# matters -- piping no lines into `sha256sum -c` can exit 0, which would skip verification
# silently if the checksums file ever changed shape.
RUN line="$(grep " $(ls quark_Linux_*.tar.gz)$" "quark_${VERSION}_checksums.txt")"; \
    test -n "$line" || { echo "ERROR: no checksum line for $(ls quark_Linux_*.tar.gz)." >&2; exit 1; }; \
    echo "$line" | sha256sum -c -
RUN tar xzf quark_Linux_*.tar.gz quark

# Debian, not alpine: the published binaries are dynamically linked against glibc -- they carry
# PT_INTERP /lib/ld-linux-*.so and need libc.so.6. That is not a GoReleaser misconfiguration;
# CGO_ENABLED=0 is honored (go version -m records it) and the binary comes out dynamic anyway,
# reproducibly, from a plain local build. Under musl they fail at exec with a bare "no such file
# or directory". A glibc base runs them either way, so this stays correct if that ever changes.
FROM debian:13-slim

# ARG does not cross a FROM, so VERSION is re-declared here for the version label.
ARG VERSION

# What GHCR reads to show the repository, description and license on the package page.
LABEL org.opencontainers.image.title="Quark" \
      org.opencontainers.image.description="Your own private cloud, running in your house. Photos, files, documents — all on hardware you own, off servers you don't trust." \
      org.opencontainers.image.source="https://github.com/autobutler-org/quark" \
      org.opencontainers.image.licenses="MIT-0" \
      org.opencontainers.image.version="${VERSION}"

# tzdata: Quark's calendar and backup schedules resolve local times, and slim ships no zoneinfo.
# ffmpeg: ffmpegutil shells out to `ffmpeg` and `ffprobe` by bare name through exec.LookPath, so
# without them every video thumbnail and transcode fails. It is a few hundred MB with its codecs
# and it ships whether or not the deployment ever touches video -- see docs/container.md.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates ffmpeg tzdata \
 && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /fetch/quark /usr/local/bin/quark

# The user has to be named "quark": storageutil.GetDataDir() resolves to /var/lib/quark/data only
# when user.Current().Username == "quark" (pkg/util/storageutil/dir.go). Under any other name the
# state lands in $HOME/quark/data instead, which is not the volume declared below.
RUN useradd --system --user-group --home-dir /var/lib/quark --shell /usr/sbin/nologin quark \
 && mkdir -p /var/lib/quark/data \
 && chown -R quark:quark /var/lib/quark
USER quark

# QUARK_INSECURE: TLS terminates at the ingress in every deployment this image targets. Unset it
# and set HTTPS_PORT to use Quark's own self-signed certificate instead.
ENV PORT=8080 \
    QUARK_INSECURE=true \
    GIN_MODE=release
EXPOSE 8080
# The whole root, not just data/: remoteutil.stateDir() puts tsnet state in the sibling
# /var/lib/quark/tsnet, so mounting only data/ discards any tailnet enrollment.
VOLUME /var/lib/quark
# Split so the default is `quark serve` while `docker run <image> version` still reaches the CLI;
# folding "serve" into the ENTRYPOINT makes every other subcommand unreachable.
ENTRYPOINT ["quark"]
CMD ["serve"]

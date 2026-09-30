# LazyFS, the FUSE file system run.bash cuts the power under (#2517). The powercut
# writer and run.bash are mounted in by `make test/chaos/powercut`, so this image
# only changes when LazyFS does.
FROM ubuntu:24.04

ARG LAZYFS_COMMIT=fa7d32ee9710d55a7e529ac3c375f6616563c78b

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates cmake fuse3 g++ git libfmt-dev libfuse3-dev libspdlog-dev make \
    && rm -rf /var/lib/apt/lists/*

# lazyfs.patch builds against the distribution's spdlog instead of downloading a
# release tarball at configure time.
COPY lazyfs.patch /tmp/lazyfs.patch
RUN git clone https://github.com/dsrhaslab/lazyfs.git /opt/lazyfs \
    && cd /opt/lazyfs \
    && git checkout "$LAZYFS_COMMIT" \
    && git apply /tmp/lazyfs.patch \
    && cd libs/libpcache && ./build.sh \
    && cd ../../lazyfs && ./build.sh \
    && ln -s /opt/lazyfs/lazyfs/build/lazyfs /usr/local/bin/lazyfs

ENV LD_LIBRARY_PATH=/opt/lazyfs/libs/libpcache/build

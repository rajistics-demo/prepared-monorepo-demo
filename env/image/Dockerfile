# syntax=docker/dockerfile:1.7
#
# Prepared sandbox image for the synthetic monorepo demo.
#
# Extends the exact agent-server release image that Rajistics runs (1.50.1-python,
# linux/amd64 digest below). Entrypoint, user, working dir and environment are
# inherited unchanged; CI compares them against the base config.
#
# Targets:
#   toolchain  base + pinned Ruby + compiled, keyed, read-only gem bundle
#   prepared   toolchain + read-only repo seed, DB fixtures, service image tarballs,
#              lock.json and the workspace scripts
#
# Build context is the repository root. `prepared` also needs build/context/,
# which env/scripts/assemble-context.sh creates in CI. Never build this on the
# Rajistics node.

ARG BASE_IMAGE=ghcr.io/openhands/agent-server:1.50.1-python@sha256:56758362c614dac19842b02a61cb21220f3008321c0d8c75d881d617f6507129

FROM ${BASE_IMAGE} AS ruby-build
USER root
ARG RUBY_VERSION=3.4.11
ARG RUBY_SHA256=f79c6e789ce4f30f77c88a40b23b93e2547c512a843dc17db27ab1f5cc66f4e4
# Only the base image's pinned Debian snapshot source is used, so package
# versions are reproducible.
RUN set -eux; \
    mkdir -p /tmp/apt-parts; cp /etc/apt/sources.list.d/debian.sources /tmp/apt-parts/; \
    apt-get -o Dir::Etc::SourceParts=/tmp/apt-parts -o Acquire::Retries=5 update; \
    apt-get -o Dir::Etc::SourceParts=/tmp/apt-parts install -y --no-install-recommends \
      build-essential autoconf bison ca-certificates curl xz-utils \
      libyaml-dev libssl-dev zlib1g-dev libffi-dev libgmp-dev libreadline-dev; \
    curl -fsSLo /tmp/ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.xz"; \
    echo "${RUBY_SHA256}  /tmp/ruby.tar.xz" | sha256sum -c -; \
    mkdir /tmp/ruby; tar -xJf /tmp/ruby.tar.xz -C /tmp/ruby --strip-components=1; \
    cd /tmp/ruby; \
    ./configure --prefix="/opt/rubies/${RUBY_VERSION}" --enable-shared --disable-install-doc; \
    make -j"$(nproc)"; make install; \
    "/opt/rubies/${RUBY_VERSION}/bin/ruby" -v

FROM ${BASE_IMAGE} AS toolchain
USER root
ARG RUBY_VERSION=3.4.11
# Toolchain and libpq stay in the image so a task whose lockfile differs from
# the prepared one can still build gems into a task-local path.
RUN set -eux; \
    mkdir -p /tmp/apt-parts; cp /etc/apt/sources.list.d/debian.sources /tmp/apt-parts/; \
    apt-get -o Dir::Etc::SourceParts=/tmp/apt-parts -o Acquire::Retries=5 update; \
    apt-get -o Dir::Etc::SourceParts=/tmp/apt-parts install -y --no-install-recommends \
      build-essential pkg-config git \
      libpq5 libpq-dev libyaml-0-2 libyaml-dev libssl-dev zlib1g-dev libffi8 libffi-dev libgmp-dev; \
    rm -rf /var/lib/apt/lists/* /tmp/apt-parts; \
    command -v python3; command -v docker; docker compose version
COPY --from=ruby-build /opt/rubies /opt/rubies
RUN set -eux; \
    for b in ruby gem bundle bundler rake irb erb; do \
      ln -sf "/opt/rubies/${RUBY_VERSION}/bin/$b" "/usr/local/bin/$b"; \
    done; \
    ruby -v; bundle -v

COPY env/pins.json /opt/prepared/src/env/pins.json
COPY env/keys/keys.py /opt/prepared/bin/keys.py
COPY server/Gemfile server/Gemfile.lock server/.ruby-version /opt/prepared/src/server/
# Gems install into /opt/prepared/bundle/<bundle_key>. Bundler's writable state
# goes to throwaway paths here and to task-local paths at run time.
RUN set -eux; \
    key="$(python3 /opt/prepared/bin/keys.py bundle --repo /opt/prepared/src)"; \
    dest="/opt/prepared/bundle/${key}"; \
    cd /opt/prepared/src/server; \
    BUNDLE_PATH="$dest" BUNDLE_FROZEN=true BUNDLE_APP_CONFIG=/tmp/bundle-config \
      BUNDLE_USER_HOME=/tmp/bundle-home BUNDLE_JOBS="$(nproc)" bundle install; \
    BUNDLE_PATH="$dest" BUNDLE_FROZEN=true BUNDLE_APP_CONFIG=/tmp/bundle-config BUNDLE_USER_HOME=/tmp/bundle-home \
      bundle exec ruby -e 'require "pg"; abort("libpq too old") unless PG.library_version >= 140000; puts "libpq #{PG.library_version}"'; \
    python3 /opt/prepared/bin/keys.py bundle --repo /opt/prepared/src --json > "${dest}.key.json"; \
    rm -rf "$dest"/ruby/*/cache /tmp/bundle-config /tmp/bundle-home /root/.local/share/gem; \
    ln -sfn "$key" /opt/prepared/bundle/current; \
    chmod -R a-w /opt/prepared
USER openhands
WORKDIR /

FROM toolchain AS prepared
USER root
COPY build/context/images/ /opt/prepared/images/
COPY build/context/fixtures/ /opt/prepared/fixtures/
COPY build/context/seed/repo.git/ /opt/prepared/seed/repo.git/
COPY build/context/lock.json /opt/prepared/lock.json
COPY --chmod=0555 env/image/prepare-workspace env/image/oh-cleanup env/image/oh-phase env/image/oh-verify /usr/local/bin/
COPY --chmod=0444 env/image/oh_common.py /usr/local/lib/oh-prepared/oh_common.py
RUN set -eux; \
    chown -R root:root /opt/prepared; \
    chmod -R a-w /opt/prepared; \
    find /opt/prepared -type d -exec chmod 0555 {} +; \
    git config --system --add safe.directory /opt/prepared/seed/repo.git
USER openhands
WORKDIR /

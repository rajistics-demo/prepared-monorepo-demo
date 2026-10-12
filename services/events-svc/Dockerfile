# syntax=docker/dockerfile:1.7
FROM rust:1.98-slim-trixie@sha256:4cd829461bd5c4d511c32e269da9cb8929223b666519d8004e35fc8d1d771ab7 AS build
WORKDIR /src
# A CI build once timed out on every parallel static.crates.io download. Fewer,
# retried connections make that less likely; they do not change the output.
ENV CARGO_NET_RETRY=10 CARGO_HTTP_MULTIPLEXING=false CARGO_HTTP_TIMEOUT=60
COPY Cargo.toml Cargo.lock ./
COPY src src
COPY migrations migrations
RUN cargo build --release --locked

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
COPY --from=build /src/target/release/events-svc /usr/local/bin/events-svc
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/events-svc"]
CMD ["serve"]

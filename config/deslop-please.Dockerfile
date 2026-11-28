ARG IMAGE
FROM ${IMAGE}
ARG URL
ARG REV
ARG INDEXERS
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates nodejs npm python3 python3-pip \
  && rm -rf /var/lib/apt/lists/* \
  && rustup component add rust-analyzer rust-src \
  && cargo install --git "$URL" --rev "$REV" --locked deslop-please \
  && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git" \
  && npm install -g --ignore-scripts --no-audit --no-fund $INDEXERS \
  && useradd -m deslop \
  && install -d -o deslop -g deslop /work
ENV CARGO_HOME=/home/deslop/.cargo
USER deslop
WORKDIR /work

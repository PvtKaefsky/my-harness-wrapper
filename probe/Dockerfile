FROM debian:13-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends bash coreutils diffutils findutils gawk git grep jq procps sed \
  && rm -rf /var/lib/apt/lists/* \
  && git config --system --add safe.directory '*'

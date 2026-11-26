FROM debian:13-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends bash coreutils diffutils findutils gawk git grep jq procps python3 python3-pip sed \
  && rm -rf /var/lib/apt/lists/* \
  && python3 -m pip install --no-cache-dir --break-system-packages hydra-core==1.3.2 python-dotenv==1.0.1 \
  && git config --system --add safe.directory '*'

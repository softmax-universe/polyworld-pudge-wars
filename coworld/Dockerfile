# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS nim
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc g++ git curl ca-certificates xz-utils libssl-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/nim-lang/nightlies/releases/download/2026-04-24-version-2-2-bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef/nim-2.2.10-linux_x64.tar.xz \
      | tar xJ -C /opt \
    && ln -s /opt/nim-2.2.10 /opt/nim
ENV PATH=/opt/nim/bin:$PATH
RUN curl -fsSL -o /usr/local/bin/nimby \
      https://github.com/treeform/nimby/releases/download/0.2.1/nimby-Linux-X64 \
    && chmod +x /usr/local/bin/nimby
WORKDIR /src/pudgewars
COPY --from=engine pudgewars.nimble nimby.lock config.nims ./
ENV PUDGEWARS_DEPS=/root/.nimby/pkgs
RUN nimby create && nimby sync nimby.lock -g
COPY --from=engine src ./src
COPY --from=engine examples/pudge_wars ./examples/pudge_wars
RUN nim c -d:ssl -d:release --passC:-flto --passL:-flto \
      -o:/out/pwleague examples/pudge_wars/episodes.nim

FROM ubuntu:24.04 AS league
RUN apt-get update && apt-get install -y --no-install-recommends libssl3 libcurl4t64 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=nim /out/pwleague /usr/local/bin/pwleague
CMD ["pwleague"]

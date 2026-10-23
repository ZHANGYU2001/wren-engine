ARG DOCKER_HUB_MIRROR=docker.io
FROM ${DOCKER_HUB_MIRROR}/library/python:3.11.17-slim-bookworm AS builder

ARG ENV
ENV ENV=$ENV

# Maintained Python 3.11 patch runtime; old Buster image failed parser/install diagnostics.
RUN sed -i 's|http://deb.debian.org|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends build-essential pkg-config default-libmysqlclient-dev libpq-dev libssl-dev git curl \
    && rm -rf /var/lib/apt/lists/*

# Install rust
# [deployment patch] rustup/cargo 走 rsproxy.cn 国内镜像
ENV RUSTUP_DIST_SERVER=https://rsproxy.cn \
    RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
RUN curl --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 --proto '=https' --tlsv1.2 -sSf https://rsproxy.cn/rustup-init.sh -o /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y --profile minimal \
    && rm /tmp/rustup-init.sh \
    && /root/.cargo/bin/cargo --version
ENV PATH="/root/.cargo/bin:$PATH"
RUN mkdir -p /root/.cargo && \
    printf '[source.crates-io]\nreplace-with = "rsproxy"\n\n[source.rsproxy]\nregistry = "sparse+https://rsproxy.cn/index/"\n' \
    > /root/.cargo/config.toml

# Install justfile
# The installer endpoint returns HTTP 403 on this machine. Use the configured
# rsproxy Cargo source and a pinned tool version instead of a remote shell script.
RUN cargo install --locked --version 1.40.0 --root /usr just && just --version

    # python
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # pip
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
    # poetry
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_VIRTUALENVS_CREATE=1

RUN pip install poetry==2.1.1

COPY --from=wren-core-py . /wren-core-py
COPY --from=wren-core . /wren-core
COPY --from=wren-core-base . /wren-core-base

WORKDIR /app
COPY . .
ARG PYPI_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/
ENV PIP_INDEX_URL=${PYPI_INDEX_URL}
# [deployment patch] 清华 PyPI 镜像加速（poetry 无 mirror 环境变量，
# 用source add + Poetry 2.x的lock重指包源，默认保留已锁定版本；
# /wren-core-py 是 build-core 阶段内部的独立 poetry 工程，一并处理）
RUN --mount=type=cache,id=wrenai-poetry-ibis,target=/root/.cache/pypoetry \
    poetry source add --priority=primary domestic "${PIP_INDEX_URL}" \
    && poetry lock --verbose \
    && cd /wren-core-py \
    && poetry source add --priority=primary domestic "${PIP_INDEX_URL}" \
    && poetry lock --verbose \
    && cd /app
# Keep all pinned fixture files while avoiding their large Git histories.
COPY tools/git-test-data-fetch.sh /usr/local/bin/git
ARG TEST_DATA_HISTORY_DEPTH=1
RUN --mount=type=cache,id=wrenai-cargo-registry,target=/root/.cargo/registry \
    --mount=type=cache,id=wrenai-cargo-git-history-${TEST_DATA_HISTORY_DEPTH},target=/root/.cargo/git \
    --mount=type=cache,id=wrenai-poetry-ibis,target=/root/.cache/pypoetry \
    sed -i 's/\r$//' /usr/local/bin/git \
    && chmod +x /usr/local/bin/git \
    && CARGO_NET_GIT_FETCH_WITH_CLI=true just install --without dev --verbose


FROM ${DOCKER_HUB_MIRROR}/library/python:3.11.17-slim-bookworm AS runtime

RUN sed -i 's|http://deb.debian.org|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends curl gnupg \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /tmp/microsoft.asc \
    && gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg /tmp/microsoft.asc \
    && rm /tmp/microsoft.asc \
    && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list -o /etc/apt/sources.list.d/mssql-release.list \
    && apt-get -o Acquire::Retries=3 update

# Install msodbcsql 18 driver for mssql
RUN ACCEPT_EULA=Y apt-get -o Acquire::Retries=3 -y install unixodbc-dev msodbcsql18

# Install libmysqlclient-dev for mysql
RUN apt-get -o Acquire::Retries=3 install -y default-libmysqlclient-dev

# libpq-dev is required for psycopg2
RUN apt-get -o Acquire::Retries=3 -y install libpq-dev \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/app/.venv \
    PATH="/app/.venv/bin:$PATH" \
    REMOTE_FUNCTION_LIST_PATH=/resources/function_list

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
COPY app app
COPY resources resources

RUN python -c "import wren_core, ibis, duckdb, orjson, oracledb, pyodbc, psycopg; print('Native connector imports OK')"

EXPOSE 8000

CMD ["fastapi", "run"]

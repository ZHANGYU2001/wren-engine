ARG DOCKER_HUB_MIRROR=docker.io
# [deployment] wren-engine 多阶段源码构建
# 原 CI 流程：先在 wren-core-legacy 里 mvnw install 产出 executable jar，
# 再单独 docker build。这里合并为一次镜像构建。
# 单镜像构建诊断：docker build --build-arg DOCKER_HUB_MIRROR=docker.m.daocloud.io -t wrenai/wren-engine:local .
# 应用启动统一使用项目根目录start-wrenai.ps1的全量Compose入口。

FROM ${DOCKER_HUB_MIRROR}/library/maven:3.9-eclipse-temurin-21 AS builder

# 阿里云 Maven 镜像加速
RUN mkdir -p /root/.m2 && \
    printf '<settings><mirrors><mirror><id>aliyun</id><mirrorOf>central</mirrorOf><url>https://maven.aliyun.com/repository/public</url></mirror></mirrors></settings>' \
    > /root/.m2/settings.xml

COPY wren-core-legacy /src
WORKDIR /src
# [deployment patch] Windows 检出导致全部文本文件为 CRLF：脚本无法执行
# （exit 127）、jvm.config 传 \r 给 java、checkstyle 报 4 万+ 违规。
# 统一将 /src 下所有文本文件转回 LF（grep -Il 自动排除二进制）
RUN grep -Il '' -r /src 2>/dev/null | xargs -r -d '\n' sed -i 's/\r$//' \
    && chmod +x mvnw
# [deployment patch] maven 官方镜像的 MAVEN_CONFIG=/root/.m2 会被 mvnw
# 当作额外 CLI 参数（"Unknown lifecycle phase /root/.m2"），unset 掉。
# git-commit-id 插件要求 .git 目录（COPY 进容器的源码没有，Windows 下子模块
# .git 也只是文件指针），跳过；dependency cache mount 避免失败后全量重下
RUN --mount=type=cache,target=/root/.m2/repository \
    unset MAVEN_CONFIG && ./mvnw clean install -B -DskipTests \
        -Dmaven.gitcommitid.skip=true -P exec-jar

FROM ${DOCKER_HUB_MIRROR}/library/eclipse-temurin:21
LABEL maintainer="https://www.canner.io/"
WORKDIR /usr/src/app

RUN apt-get update && \
    apt-get install -y curl gpg lsb-release && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y postgresql-client-13 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/wren-server/target/wren-server-*-executable.jar ./
COPY wren-core-legacy/docker/entrypoint.sh ./
# [deployment patch] CRLF 归一化（同上）
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh

# jar 文件名含版本号，运行时动态解析
CMD ./entrypoint.sh $(ls wren-server-*-executable.jar | head -1) ${MAX_HEAP_SIZE} ${MIN_HEAP_SIZE}

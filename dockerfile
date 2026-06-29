FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

# 必要パッケージ
RUN apt update && apt install -y --no-install-recommends \
    sudo \
    curl \
    git \
    cron \
    tzdata \
    jq \
    && rm -rf /var/lib/apt/lists/*

# タイムゾーン
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# ユーザー
RUN useradd -m -s /bin/bash r.h

# 作業ディレクトリ
WORKDIR /home/r.h

# コピー
COPY docker/ /home/r.h/docker/

# 権限
RUN chown -R r.h:r.h /home/r.h/docker && \
    find /home/r.h/docker -type f -name "*.sh" -exec chmod +x {} \;

# entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
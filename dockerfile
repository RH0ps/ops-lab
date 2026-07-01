FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

RUN apt update && apt install -y --no-install-recommends \
    sudo \
    curl \
    git \
    cron \
    ca-certificates \
    tzdata \
    jq \
    bash \
    && rm -rf /var/lib/apt/lists/*

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

RUN useradd -m -s /bin/bash r.h

WORKDIR /home/r.h

COPY . /home/r.h/docker/

RUN chown -R r.h:r.h /home/r.h/docker && \
    find /home/r.h/docker -type f -name "*.sh" -exec chmod +x {} \;

ENTRYPOINT ["bash", "/home/r.h/docker/entrypoint.sh"]
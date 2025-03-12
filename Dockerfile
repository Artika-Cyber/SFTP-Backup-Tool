FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    liblz4-tool \
    openssh-client \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

COPY main.sh /app/main.sh
RUN chmod +x /app/main.sh

WORKDIR /app

ENTRYPOINT ["/app/main.sh"]
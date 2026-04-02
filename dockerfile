FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Core dependencies + Chrome
RUN apt-get update && apt-get install -y \
    nodejs npm \
    xvfb x11vnc novnc websockify fluxbox git \
    dbus-x11 dbus fonts-liberation libnss3 \
    curl wget gnupg grep ffmpeg \
    && rm -rf /var/lib/apt/lists/*
    
COPY package.json .
RUN npm install

RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# noVNC
RUN git clone https://github.com/novnc/noVNC.git /opt/novnc

# (Optional) MediaMTX for streaming
RUN wget https://github.com/aler9/mediamtx/releases/download/v1.9.3/mediamtx_v1.9.3_linux_amd64.tar.gz && \
    tar -xzf mediamtx_v1.9.3_linux_amd64.tar.gz -C /usr/local/bin/ mediamtx && \
    rm mediamtx_v1.9.3_linux_amd64.tar.gz

COPY mediamtx.yml /etc/mediamtx.yml
COPY entrypoint.sh /entrypoint.sh

COPY proxy.js /app/proxy.js

RUN chmod +x /entrypoint.sh

EXPOSE 6080 8554 8889 9222

CMD ["/entrypoint.sh"]
#!/bin/bash
set -e

echo "🚀 Starting Browser Container..."

# DBus (needed for Chrome)
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# OPTIONAL: streaming (RTSP/WebRTC)
/usr/local/bin/mediamtx /etc/mediamtx.yml &

# Virtual display
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
sleep 1

# Window manager
fluxbox &

# VNC server
x11vnc -display :99 -rfbport 5900 -nopw -forever -shared -listen 0.0.0.0 &

# noVNC (web UI)
/opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080 &

sleep 5

# OPTIONAL: ffmpeg stream
ffmpeg -nostdin -f x11grab -video_size 1280x720 -framerate 30 -i :99 \
       -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
       -f rtsp rtsp://localhost:8554/mystream &

echo "🌐 Launching Chrome..."

# 🔥 IMPORTANT: open a page (ensures /json is not empty)
google-chrome \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --no-first-run \
  --no-default-browser-check \
  --disable-extensions \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --remote-debugging-port=9222 \
  --remote-debugging-address=0.0.0.0 \
  --remote-debugging-host=0.0.0.0 \
  --remote-allow-origin=* \
  --user-data-dir=/tmp/chrome \
  --window-size=1280,720 \
  "https://www.google.com" &

echo "⏳ Waiting for Chrome CDP..."

# 🔥 REAL readiness check
sleep 5 
for i in {1..10}; do
  if curl -s "http://localhost:9222/json >/dev/null"; then
    echo "chrome is responding"
    break
  fi
  echo "try"
  sleep 2
done

echo "✅ Chrome ready (CDP available)"

sleep 2

echo "starting proxy...."
ls -l /app

cd /app
node proxy.js 

sleep 2
ps aux | grep node

wait
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
  about:blank \
  > /tmp/chrome.log 2>&1 &

CHROME_PID=$!

# 🔥 REAL readiness check
echo "⏳ Waiting for Chrome CDP..."

# Give Chrome some time to boot
sleep 5

MAX_RETRIES=20
RETRY_DELAY=2

for i in $(seq 1 $MAX_RETRIES); do
  JSON=$(curl -s http://localhost:9222/json || true)

  # ✅ Check if ANY target exists (not just websocket)
  COUNT=$(echo "$JSON" | grep -o "webSocketDebuggerUrl" | wc -l)

  if [ "$COUNT" -gt 0 ]; then
    echo "✅ Chrome CDP ready with $COUNT target(s)"
    break
  fi

  echo "⏳ waiting... ($i/$MAX_RETRIES)"
  sleep $RETRY_DELAY
done

# 🔥 FINAL VALIDATION
FINAL_COUNT=$(curl -s http://localhost:9222/json | grep -o "webSocketDebuggerUrl" | wc -l)

if [ "$FINAL_COUNT" -eq 0 ]; then
  echo "❌ Chrome CDP not ready — no debuggable targets"
  exit 1
fi

echo "🚀 Chrome fully ready with $FINAL_COUNT target(s)"

echo "chrome fully ready"

echo "starting proxy...."

cd /app
node proxy.js &

sleep 2
ps aux | grep node

echo "browser container is stable"

tail -f /dev/null
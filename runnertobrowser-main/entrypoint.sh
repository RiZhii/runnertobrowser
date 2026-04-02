#!/bin/bash
set -e

echo "Starting Browser Container..."

# -------------------------------
# DBus (required for Chrome)
# -------------------------------
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# -------------------------------
# Virtual Display
# -------------------------------
echo "🖥️ Starting Xvfb..."
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
sleep 2

# -------------------------------
# Window Manager
# -------------------------------
echo "Starting Fluxbox..."
fluxbox &

# -------------------------------
# VNC Server
# -------------------------------
echo "Starting VNC..."
x11vnc -display :99 -rfbport 5900 -nopw -forever -shared -listen 0.0.0.0 &

# -------------------------------
# noVNC
# -------------------------------
echo "Starting noVNC..."
/opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080 &

sleep 3

# -------------------------------
# Launch Chrome (CDP enabled)
# -------------------------------
echo "Launching Chrome..."

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
  --user-data-dir=/tmp/chrome \
  --window-size=1280,720 \
  about:blank \
  > /tmp/chrome.log 2>&1 &

CHROME_PID=$!

# -------------------------------
# Wait for CDP
# -------------------------------
echo "⏳ Waiting for Chrome CDP..."

MAX_RETRIES=30
RETRY_DELAY=2

for i in $(seq 1 $MAX_RETRIES); do
  if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "CDP endpoint reachable"
    break
  fi

  echo "waiting for CDP... ($i/$MAX_RETRIES)"
  sleep $RETRY_DELAY
done

# -------------------------------
# Ensure at least one target
# -------------------------------
echo "Creating CDP page..."

curl -s "http://localhost:9222/json/new?about:blank" > /dev/null || true

sleep 2

TARGET_COUNT=$(curl -s http://localhost:9222/json | grep -o "webSocketDebuggerUrl" | wc -l)

if [ "$TARGET_COUNT" -eq 0 ]; then
  echo "No CDP targets available"
  exit 1
fi

echo "Chrome ready with $TARGET_COUNT target(s)"

echo "Targets:"
curl -s http://localhost:9222/json | grep url || true

# -------------------------------
# Start Proxy
# -------------------------------
echo "Starting proxy..."

cd /app
node proxy.js &

sleep 2

if ! ps aux | grep -v grep | grep -q "node proxy.js"; then
  echo "Proxy failed to start"
  exit 1
fi

echo "Proxy running"

# -------------------------------
# Container Ready
# -------------------------------
echo "Browser container is READY"

# Keep container alive
tail -f /dev/null
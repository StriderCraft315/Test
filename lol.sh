#!/bin/bash

echo "=== NUCLEAR OPTION: Clearing Ports 443 & 2022 ==="

# Stop Wings service
echo "1. Stopping Wings service..."
sudo systemctl stop wings

# Kill ALL wings processes
echo "2. Killing all Wings processes..."
sudo pkill -f wings
sudo pkill -f pterodactyl

# Clear port 443 aggressively
echo "3. Clearing port 443..."
sudo fuser -k 443/tcp 2>/dev/null
sudo lsof -ti :443 | xargs sudo kill -9 2>/dev/null

# Clear port 2022 aggressively  
echo "4. Clearing port 2022..."
sudo fuser -k 2022/tcp 2>/dev/null
sudo lsof -ti :2022 | xargs sudo kill -9 2>/dev/null

# Double-check and kill any remaining processes
echo "5. Final cleanup..."
for port in 443 2022; do
    PID=$(sudo lsof -ti :$port 2>/dev/null)
    if [[ ! -z "$PID" ]]; then
        echo "🛑 Still found process $PID on port $port - nuking..."
        sudo kill -9 $PID 2>/dev/null
    fi
done

# Wait for dust to settle
sleep 3

# Verify ports are FREE
echo ""
echo "=== VERIFICATION ==="
echo "Port 443 status:"
if sudo ss -tulpn | grep ":443 " > /dev/null; then
    echo "❌ PORT 443 STILL IN USE:"
    sudo ss -tulpn | grep ":443 "
else
    echo "✅ PORT 443 IS FREE"
fi

echo ""
echo "Port 2022 status:"
if sudo ss -tulpn | grep ":2022 " > /dev/null; then
    echo "❌ PORT 2022 STILL IN USE:"
    sudo ss -tulpn | grep ":2022 "
else
    echo "✅ PORT 2022 IS FREE"
fi

# Start Wings
echo ""
echo "6. Starting Wings..."
sudo systemctl start wings

# Final status
echo ""
echo "=== FINAL STATUS ==="
sudo systemctl status wings --no-pager -l

echo ""
echo "Ports after Wings start:"
for port in 443 2022; do
    if sudo ss -tulpn | grep ":${port} " | grep -q "wings"; then
        echo "✅ Port $port: Now secured by Wings"
    else
        echo "❌ Port $port: Still not used by Wings"
    fi
done

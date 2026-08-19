#!/bin/bash

# ====== COLORS ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ====== CONFIG ======
SERVER_IP="161.118.186.229"
TOKEN="MyStrongSecret123"
PORT_RANGE_START=10000
PORT_RANGE_END=30000

# ====== FUNCTIONS ======

install_frps() {
  echo -e "\( {YELLOW}Installing frps (server)... \){NC}"
  cd /tmp || exit
  FRP_VER=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "\K[^"]+' | sed 's/v//')
  wget -q https://github.com/fatedier/frp/releases/download/v\( {FRP_VER}/frp_ \){FRP_VER}_linux_amd64.tar.gz
  tar -xzf frp_${FRP_VER}_linux_amd64.tar.gz
  cd frp_${FRP_VER}_linux_amd64 || exit

  sudo cp frps /usr/local/bin/
  sudo mkdir -p /etc/frp /var/log/frp

  sudo tee /etc/frp/frps.toml > /dev/null << EOF
bindPort = 7000
auth.method = "token"
auth.token = "$TOKEN"
maxPortsPerClient = 30
allowPorts = [
  { start = $PORT_RANGE_START, end = $PORT_RANGE_END }
]
log.to = "/var/log/frp/frps.log"
log.level = "info"
EOF

  sudo tee /etc/systemd/system/frps.service > /dev/null << 'EOF'
[Unit]
Description=frp server
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now frps
  echo -e "\( {GREEN}✅ frps installed and started \){NC}"
  echo -e "IP: $SERVER_IP | Port: 7000 | Token: $TOKEN"
}

install_frpc() {
  echo -e "\( {YELLOW}Installing frpc (client)... \){NC}"
  cd /tmp || exit
  FRP_VER=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "\K[^"]+' | sed 's/v//')
  wget -q https://github.com/fatedier/frp/releases/download/v\( {FRP_VER}/frp_ \){FRP_VER}_linux_amd64.tar.gz
  tar -xzf frp_${FRP_VER}_linux_amd64.tar.gz
  cd frp_${FRP_VER}_linux_amd64 || exit

  sudo cp frpc /usr/local/bin/
  sudo mkdir -p /etc/frp

  # Create basic config
  sudo tee /etc/frp/frpc.toml > /dev/null << EOF
serverAddr = "$SERVER_IP"
serverPort = 7000
auth.token = "$TOKEN"

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 10022
EOF

  sudo tee /etc/systemd/system/frpc.service > /dev/null << 'EOF'
[Unit]
Description=frp client
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now frpc
  echo -e "\( {GREEN}✅ frpc installed and started \){NC}"
}

show_ports() {
  echo -e "\n\( {BLUE}=== Current Ports === \){NC}"
  if [[ -f /etc/frp/frpc.toml ]]; then
    echo -e "\( {YELLOW}Client config (/etc/frp/frpc.toml): \){NC}"
    grep -E "name =|type =|localPort =|remotePort =" /etc/frp/frpc.toml | sed 's/^/  /'
  else
    echo "No frpc config found"
  fi

  echo
  if systemctl is-active --quiet frpc; then
    echo -e "\( {GREEN}frpc is running \){NC}"
    journalctl -u frpc -n 10 --no-pager | grep -E "start proxy|error|success" || true
  else
    echo -e "\( {RED}frpc is not running \){NC}"
  fi

  if systemctl is-active --quiet frps; then
    echo -e "\( {GREEN}frps is running \){NC}"
  fi
}

delete_frp() {
  echo -e "\( {RED}What do you want to remove? \){NC}"
  echo "1) Remove frps (server only)"
  echo "2) Remove frpc (client only)"
  echo "3) Remove both"
  read -rp "Choice [1-3]: " choice

  case $choice in
    1)
      sudo systemctl stop frps 2>/dev/null
      sudo systemctl disable frps 2>/dev/null
      sudo rm -f /usr/local/bin/frps /etc/systemd/system/frps.service
      sudo rm -rf /etc/frp /var/log/frp
      sudo systemctl daemon-reload
      echo -e "\( {GREEN}frps removed \){NC}"
      ;;
    2)
      sudo systemctl stop frpc 2>/dev/null
      sudo systemctl disable frpc 2>/dev/null
      sudo rm -f /usr/local/bin/frpc /etc/systemd/system/frpc.service /etc/frp/frpc.toml
      sudo systemctl daemon-reload
      echo -e "\( {GREEN}frpc removed \){NC}"
      ;;
    3)
      sudo systemctl stop frps frpc 2>/dev/null
      sudo systemctl disable frps frpc 2>/dev/null
      sudo rm -f /usr/local/bin/frps /usr/local/bin/frpc
      sudo rm -f /etc/systemd/system/frps.service /etc/systemd/system/frpc.service
      sudo rm -rf /etc/frp /var/log/frp
      sudo systemctl daemon-reload
      echo -e "\( {GREEN}Both frps and frpc removed \){NC}"
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
}

auto_ports() {
  echo -e "\( {YELLOW}Auto generating ports... \){NC}"

  declare -A PORTS=(
    ["ssh"]="22/tcp"
    ["web"]="80/tcp"
    ["game"]="7777/udp"
  )

  cat > /tmp/frpc.toml << EOF
serverAddr = "$SERVER_IP"
serverPort = 7000
auth.token = "$TOKEN"

EOF

  used=()
  for name in "${!PORTS[@]}"; do
    IFS='/' read -r local_port proto <<< "${PORTS[$name]}"
    while true; do
      remote=$(( RANDOM % (PORT_RANGE_END - PORT_RANGE_START + 1) + PORT_RANGE_START ))
      [[ " ${used[*]} " =\~ " $remote " ]] && continue
      used+=("$remote")
      break
    done

    cat >> /tmp/frpc.toml << EOF
[[proxies]]
name = "$name"
type = "$proto"
localIP = "127.0.0.1"
localPort = $local_port
remotePort = $remote

EOF
    echo "→ $name → $SERVER_IP:$remote"
  done

  sudo mv /tmp/frpc.toml /etc/frp/frpc.toml
  sudo systemctl restart frpc 2>/dev/null || true
  echo -e "\( {GREEN}Done! \){NC}"
}

# ====== MENU ======
while true; do
  clear
  echo -e "\( {BLUE}================================ \){NC}"
  echo -e "${BLUE}       FRP Manager Menu         ${NC}"
  echo -e "\( {BLUE}================================ \){NC}"
  echo
  echo "1) Install frps (Server)"
  echo "2) Install frpc (Client)"
  echo "3) Show current ports"
  echo "4) Auto generate ports (Client)"
  echo "5) Delete / Uninstall frp"
  echo "6) Exit"
  echo
  read -rp "Choose an option [1-6]: " opt

  case $opt in
    1) install_frps; read -rp "Press Enter..." ;;
    2) install_frpc; read -rp "Press Enter..." ;;
    3) show_ports; read -rp "Press Enter..." ;;
    4) auto_ports; read -rp "Press Enter..." ;;
    5) delete_frp; read -rp "Press Enter..." ;;
    6) echo "Bye"; exit 0 ;;
    *) echo "Invalid option"; sleep 1 ;;
  esac
done

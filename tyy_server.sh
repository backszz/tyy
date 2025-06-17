#!/bin/bash

# 天翼云后端服务器一键部署脚本
# 使用固定端口443

echo "================================"
echo " 天翼云后端服务器 Xray 部署脚本 "
echo "================================"
echo "正在更新系统并安装必要组件..."

# 更新系统组件
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y
apt autoremove -y

# 安装基础工具
apt install -y --no-install-recommends \
    curl wget unzip tar openssl uuid-runtime net-tools \
    iproute2 iptables jq cron dnsutils

# 下载Xray核心 (固定版本1.8.4)
echo "下载Xray核心..."
ARCH=$(uname -m)
case $ARCH in
    "x86_64") ARCH="64" ;;
    "aarch64") ARCH="arm64-v8a" ;;
    *) ARCH="64" ;;
esac

XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-$ARCH.zip"
echo "下载URL: $XRAY_URL"

for i in {1..5}; do
    echo "尝试 $i/5 下载Xray核心..."
    if curl -L -o xray.zip "$XRAY_URL" --connect-timeout 30 --retry 5; then
        echo "下载成功!"
        break
    else
        echo "下载失败，等待5秒后重试..."
        sleep 5
    fi
done

if [ ! -f "xray.zip" ]; then
    echo "错误：无法下载Xray核心，请手动下载并上传到服务器"
    exit 1
fi

echo "安装Xray核心..."
unzip -q xray.zip
rm -f xray.zip geoip.dat geosite.dat
chmod +x xray
mv xray /usr/local/bin/
mkdir -p /usr/local/share/xray/
mv geo* /usr/local/share/xray/

# 生成配置参数
echo "生成加密参数..."
XRAY_KEY=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$XRAY_KEY" | grep 'Private key' | awk '{print $3}')
PUBLIC_KEY=$(echo "$XRAY_KEY" | grep 'Public key' | awk '{print $3}')
UUID=$(/usr/local/bin/xray uuid)
SHORT_ID=$(openssl rand -hex 8 | head -c 16)
TARGET_DOMAIN="www.bing.com"
SERVER_PORT="443"

echo "创建配置文件..."
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": $SERVER_PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ 
        "id": "$UUID",
        "flow": "xtls-rprx-vision" 
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$TARGET_DOMAIN:443",
        "xver": 0,
        "serverNames": ["$TARGET_DOMAIN"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

# 创建日志文件
mkdir -p /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log

# 创建systemd服务
echo "创建systemd服务..."
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# 优化内核参数
echo "优化网络配置..."
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
EOF
sysctl -p

# 配置防火墙
echo "配置防火墙..."
apt install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow $SERVER_PORT/tcp
echo "y" | ufw enable

# 启动服务
echo "启动Xray服务..."
systemctl daemon-reload
systemctl enable xray
systemctl start xray

# 检查服务状态
sleep 2
echo "检查服务状态..."
if systemctl is-active --quiet xray; then
    STATUS="✅ 运行中"
else
    STATUS="❌ 未运行 (journalctl -u xray 查看日志)"
fi

# 输出配置信息
clear
echo "=========================================================="
echo "                 天翼云服务器部署完成                     "
echo "=========================================================="
echo " 服务器状态: $STATUS"
echo " 服务器IP  : $(curl -4s ifconfig.co)" 
echo " 端口      : $SERVER_PORT"
echo "----------------------------------------------------------"
echo " UUID      : $UUID"
echo " Public Key: $PUBLIC_KEY"
echo " Short ID  : $SHORT_ID"
echo " 伪装目标  : $TARGET_DOMAIN"
echo "=========================================================="
echo " 客户端配置:"
echo ""
echo " 类型: vless"
echo " 地址: [天翼云服务器IP]"
echo " 端口: 443"
echo " 用户ID: $UUID"
echo " 流控: xtls-rprx-vision"
echo " TLS类型: reality"
echo " Public Key: $PUBLIC_KEY"
echo " Short ID: $SHORT_ID"
echo " SNI: $TARGET_DOMAIN"
echo ""
echo "=========================================================="
echo " 调试命令:"
echo " 查看日志: journalctl -u xray -f"
echo " 重启服务: systemctl restart xray"
echo " 连接测试: nc -zv \$(curl -4s ifconfig.co) $SERVER_PORT"
echo "=========================================================="

#!/bin/bash
# 天翼云服务器部署脚本 (修复安装问题)
# 保存到: https://raw.githubusercontent.com/backszz/tyy/main/tyy_server_reliable.sh

echo "正在优化系统配置..."
# 禁用可能引起冲突的云监控服务
systemctl stop aliyun.service > /dev/null 2>&1
systemctl disable aliyun.service > /dev/null 2>&1

# 设置更可靠的软件源
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list

echo "正在安装必要组件(简化版)..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    curl openssl uuid-runtime iproute2

# 手动安装Xray核心
echo "手动安装Xray核心..."
mkdir -p /tmp/xray-install
cd /tmp/xray-install

# 获取最新版本号
LATEST_VERSION=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | \
    grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

echo "检测到最新版本: $LATEST_VERSION"

# 下载Xray
ARCH=$(uname -m)
case $ARCH in
    "x86_64") ARCH="64" ;;
    "aarch64") ARCH="arm64-v8a" ;;
    *) ARCH="64" ;;
esac

wget --tries=3 --timeout=30 -O Xray-linux-$ARCH.zip \
    "https://github.com/XTLS/Xray-core/releases/download/$LATEST_VERSION/Xray-linux-$ARCH.zip"

if [ ! -f "Xray-linux-$ARCH.zip" ]; then
    echo "错误：无法下载Xray核心，请手动下载"
    exit 1
fi

# 解压并安装
unzip -q Xray-linux-$ARCH.zip
mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray
mkdir -p /usr/local/share/xray/
mv geo* /usr/local/share/xray/

# 创建systemd服务
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

# 生成密钥和ID
echo "生成加密参数..."
XRAY_KEY=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$XRAY_KEY" | grep 'Private key' | awk '{print $3}')
PUBLIC_KEY=$(echo "$XRAY_KEY" | grep 'Public key' | awk '{print $3}')
UUID=$(/usr/local/bin/xray uuid)
SHORT_ID=$(openssl rand -hex 8 | head -c 16)

# 配置参数
TARGET_DOMAIN="www.bing.com"  # 伪装目标网站
SERVER_PORT="443"             # 固定监听端口

# 创建配置文件
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
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

# 创建日志目录
mkdir -p /var/log/xray
touch /var/log/xray/{access,error}.log
chown -R nobody:nogroup /var/log/xray

# 优化内核参数
echo "优化网络性能..."
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

# 配置防火墙
echo "配置防火墙规则..."
echo "y" | ufw reset
ufw default deny incoming
ufw default allow outgoing
ufw allow $SERVER_PORT/tcp
echo "y" | ufw enable

# 启动服务
systemctl daemon-reload
systemctl start xray
systemctl enable xray

# 检查服务状态
if ! systemctl is-active --quiet xray; then
    echo "警告：Xray服务启动失败，查看日志：journalctl -u xray -b"
    echo "正在尝试修复..."
    systemctl restart xray
    sleep 2
fi

# 输出配置信息
clear
echo "=============================================="
echo "  天翼云服务器部署成功！"
echo "  服务器IP: $(curl -4s ifconfig.co)"
echo "  端口: $SERVER_PORT"
echo "  UUID: $UUID"
echo "  Public Key: $PUBLIC_KEY"
echo "  Short ID: $SHORT_ID"
echo "  伪装目标: $TARGET_DOMAIN"
echo "=============================================="
echo "  服务状态: $(systemctl is-active xray)"
echo "  日志查看: journalctl -u xray -f"
echo "=============================================="

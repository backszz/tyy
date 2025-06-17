#!/bin/bash
# 天翼云服务器部署脚本 (Reality协议)
# 保存到: https://raw.githubusercontent.com/backszz/tyy/main/tyy_server.sh

# 安装Xray核心
echo "正在安装Xray核心..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成密钥和ID
XRAY_KEY=$(xray x25519)
PRIVATE_KEY=$(echo "$XRAY_KEY" | grep 'Private key' | awk '{print $3}')
PUBLIC_KEY=$(echo "$XRAY_KEY" | grep 'Public key' | awk '{print $3}')
UUID=$(xray uuid)
SHORT_ID=$(openssl rand -hex 8 | head -c 16)

# 配置参数
TARGET_DOMAIN="www.bing.com"  # 伪装目标网站
SERVER_PORT="443"             # 监听端口

# 创建配置文件
cat > /usr/local/etc/xray/config.json <<EOF
{
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

# 优化内核参数
echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# 配置防火墙
ufw allow $SERVER_PORT/tcp
ufw --force reload >/dev/null 2>&1

# 启动服务
systemctl restart xray
systemctl enable xray

# 输出配置信息
clear
echo "=================================================="
echo "  天翼云服务器部署成功！"
echo "=================================================="
echo "  服务器IP: $(curl -4s ifconfig.co)"
echo "  端口: $SERVER_PORT"
echo "  UUID: $UUID"
echo "  Public Key: $PUBLIC_KEY"
echo "  Short ID: $SHORT_ID"
echo "  伪装目标: $TARGET_DOMAIN"
echo "=================================================="
echo "  下一步：在香港服务器执行中转部署脚本"
echo "  需要提供以上输出的所有信息"
echo "=================================================="

#!/bin/bash
# 天翼云服务器部署脚本（VLESS Reality Vision）
# 执行: wget -O reality.sh https://raw.githubusercontent.com/yourrepo/reality.sh && bash reality.sh

# 配置参数
TARGET_DOMAIN="www.bing.com"  # 伪装目标网站
SERVER_PORT="443"             # 监听端口（标准HTTPS端口）

# 安装Xray
echo ""
echo "正在安装Xray核心..."
sleep 2
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成密钥和ID
echo ""
echo "正在生成加密密钥..."
sleep 2
XRAY_KEY=$(xray x25519)
PRIVATE_KEY=$(echo "$XRAY_KEY" | grep 'Private key' | awk '{print $3}')
PUBLIC_KEY=$(echo "$XRAY_KEY" | grep 'Public key' | awk '{print $3}')
UUID=$(xray uuid)
SHORT_ID=$(openssl rand -hex 8 | head -c 16)

# 创建配置文件
echo ""
echo "正在创建Reality配置..."
sleep 2
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
echo ""
echo "正在优化网络性能..."
sleep 2
echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

# 配置防火墙
echo ""
echo "配置防火墙规则..."
sleep 2
ufw allow $SERVER_PORT/tcp
ufw --force reload

# 配置每日自动重启
echo ""
echo "设置自动维护任务..."
sleep 2
crontab -l | { cat; echo "0 4 * * * /usr/bin/systemctl restart xray"; } | crontab -

# 启动服务
systemctl restart xray
systemctl enable xray

# 清理痕迹
history -c

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
echo "  客户端配置信息（保存到本地）："
echo ""
echo "类型: vless"
echo "地址: [中转服务器IP]"
echo "端口: [每日变化的端口]"
echo "用户ID: $UUID"
echo "流控: xtls-rprx-vision"
echo "TLS: reality"
echo "Public Key: $PUBLIC_KEY"
echo "Short ID: $SHORT_ID"
echo "SNI: $TARGET_DOMAIN"
echo ""
echo "=============================================="
echo "  提示：请记录以上信息，下一步将用于中转服务器配置"
echo "=============================================="

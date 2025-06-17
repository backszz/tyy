#!/bin/bash
# 天翼云服务器部署脚本 (修复版本检测问题)
# 保存到: https://raw.githubusercontent.com/backszz/tyy/main/tyy_server_fixed.sh

echo "正在安装必要组件..."
# 使用阿里云镜像源加速
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list

apt update
apt install -y --no-install-recommends \
    curl openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq

# 手动下载最新版Xray
echo "手动下载Xray核心..."

# 判断系统架构
ARCH=$(uname -m)
case $ARCH in
    "x86_64") ARCH="64" ;;
    "aarch64") ARCH="arm64-v8a" ;;
    *) ARCH="64" ;;  # 默认为64位
esac

# 获取最新版本（修复方法）
echo "获取最新版本..."
VER="1.8.4"  # 默认使用的稳定版本
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v$VER/Xray-linux-$ARCH.zip"
echo "使用稳定版本: v$VER"
echo "下载URL: $XRAY_URL"

# 使用curl重试机制
for i in {1..5}; do
    echo "尝试 $i/5 下载..."
    if curl -L -o xray.zip "$XRAY_URL" --connect-timeout 20 --retry 3; then
        echo "下载成功!"
        break
    else
        echo "下载失败，等待5秒后重试..."
        sleep 5
    fi
done

# 检查下载是否成功
if [ ! -f "xray.zip" ]; then
    echo "错误：无法下载Xray核心，请手动下载并上传到服务器"
    exit 1
fi

echo "解压安装Xray..."
unzip -q xray.zip
rm -f xray.zip geoip.dat geosite.dat
chmod +x xray
mv xray /usr/local/bin/
mkdir -p /usr/local/share/xray/
mv geo* /usr/local/share/xray/

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

# 创建配置文件和目录
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

# 创建日志目录
mkdir -p /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log

# 优化内核参数
echo "优化网络配置..."
cat >> /etc/sysctl.conf <<EOF
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
EOF
sysctl -p

# 配置防火墙(UFW)
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
    STATUS="✓ 运行中"
else
    STATUS="✗ 未运行 (journalctl -u xray 查看日志)"
fi

# 输出配置信息
clear
echo "=========================================================="
echo "                 天翼云服务器部署完成                     "
echo "=========================================================="
echo " 服务器状态: $STATUS"
echo " 服务器IP  : $(curl -4s ifconfig.co)"  # 使用更可靠的IP获取方式
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
echo " 连接测试: nc -zv $(curl -4s ifconfig.co) $SERVER_PORT"
echo "=========================================================="

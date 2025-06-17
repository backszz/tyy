#!/bin/bash

# 天翼云服务器一键部署脚本 (Nginx反代版)
# 使用Nginx监听443端口，转发到本地的8443

echo "=========================================="
echo " 天翼云服务器部署脚本 - Nginx反代版 "
echo "=========================================="
echo "正在安装必要组件..."

# 使用阿里云镜像源加速
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list

apt update
apt install -y --no-install-recommends \
    curl wget openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq iptables-persistent netcat-openbsd nginx

# 下载 Xray 核心 (固定版本 1.8.4)
echo "下载Xray核心..."
ARCH=$(uname -m)
case $ARCH in
    "x86_64") ARCH="64" ;;
    "aarch64") ARCH="arm64-v8a" ;;
    *) ARCH="64" ;;  # 默认为64位
esac

XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-$ARCH.zip"

for i in {1..5}; do
    echo "尝试 $i/5 下载..."
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
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

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
TARGET_DOMAIN="www.qq.com"  # 伪装目标网站
SERVER_PORT="8443"          # 本地监听8443端口
PUBLIC_PORT="443"           # Nginx对外监听443端口

# 创建配置文件和目录
echo "创建配置文件..."
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "info"
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

# 配置Nginx反向代理
echo "配置Nginx反向代理..."
cat > /etc/nginx/conf.d/reverse-proxy.conf <<EOF
stream {
    server {
        listen $PUBLIC_PORT;
        proxy_pass 127.0.0.1:$SERVER_PORT;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
    }
}
EOF

# 优化内核参数
echo "优化内核参数..."
cat >> /etc/sysctl.conf <<EOF
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.ip_forward = 1
EOF
sysctl -p

# 配置防火墙
echo "配置防火墙..."
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -A INPUT -p tcp --dport $PUBLIC_PORT -j ACCEPT
iptables -A INPUT -p udp --dport $PUBLIC_PORT -j ACCEPT
netfilter-persistent save

# 启动服务
echo "启动服务..."
systemctl daemon-reload
systemctl enable --now xray >/dev/null 2>&1
systemctl enable --now nginx >/dev/null 2>&1
sleep 2

# 检查服务状态
XRAY_STATUS=$(systemctl is-active xray)
NGINX_STATUS=$(systemctl is-active nginx)

if [ "$XRAY_STATUS" != "active" ]; then
    echo "Xray服务启动失败，查看日志: journalctl -u xray"
fi

if [ "$NGINX_STATUS" != "active" ]; then
    echo "Nginx服务启动失败，查看日志: journalctl -u nginx"
fi

# 获取公网IP
get_public_ip() {
    local services=(
        "ipinfo.io/ip"
        "ifconfig.me"
        "icanhazip.com"
        "api.ipify.org"
        "ip.seeip.org"
    )
    for service in "${services[@]}"; do
        ip=$(curl -4s --connect-timeout 3 "$service")
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    echo "无法获取公网IP"
}
PUBLIC_IP=$(get_public_ip)

# 输出配置信息
clear
echo "=========================================================="
echo "                 天翼云服务器部署完成                     "
echo "                  Nginx监听端口: $PUBLIC_PORT             "
echo "=========================================================="
echo " 服务器IP  : $PUBLIC_IP"
echo " 端口      : $PUBLIC_PORT"
echo "----------------------------------------------------------"
echo " UUID      : $UUID"
echo " Public Key: $PUBLIC_KEY"
echo " Short ID  : $SHORT_ID"
echo " 伪装目标  : $TARGET_DOMAIN"
echo "=========================================================="
echo " 客户端配置:"
echo ""
echo " 地址: $PUBLIC_IP"
echo " 端口: $PUBLIC_PORT"
echo " 用户ID: $UUID"
echo " 流控: xtls-rprx-vision"
echo " TLS类型: reality"
echo " Public Key: $PUBLIC_KEY"
echo " Short ID: $SHORT_ID"
echo " SNI: $TARGET_DOMAIN"
echo ""
echo "=========================================================="
echo " 防火墙状态:"
iptables -L -n -v
echo " 测试本地连接: nc -zv 127.0.0.1 $SERVER_PORT"
echo " 测试Nginx连接: nc -zv 127.0.0.1 $PUBLIC_PORT"
echo " 查看Xray日志: journalctl -u xray -f"
echo " 查看Nginx日志: journalctl -u nginx -f"
echo " 安全组: 确保开放 $PUBLIC_PORT 端口 TCP/UDP"
echo "=========================================================="

# 保存配置到文件
cat > server_config.txt <<EOF
天翼云服务器配置 (Nginx反代):
------------------------------
地址: $PUBLIC_IP
端口: $PUBLIC_PORT
用户ID: $UUID
流控: xtls-rprx-vision
TLS类型: reality
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
SNI: $TARGET_DOMAIN
------------------------------
EOF
echo "配置已保存到服务器: server_config.txt"

# 验证配置
echo "验证配置..."
echo "1. 检查Xray状态: systemctl status xray"
systemctl status xray | head -n 10
echo ""
echo "2. 检查Nginx状态: systemctl status nginx"
systemctl status nginx | head -n 10
echo ""
echo "3. 测试本地连接: nc -zv 127.0.0.1 $SERVER_PORT"
nc -zv 127.0.0.1 $SERVER_PORT
echo ""
echo "4. 测试Nginx转发: nc -zv 127.0.0.1 $PUBLIC_PORT"
nc -zv 127.0.0.1 $PUBLIC_PORT
echo ""
echo "如果所有测试都成功，则可以在香港服务器上部署中转节点"

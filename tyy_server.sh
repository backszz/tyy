#!/bin/bash

# 天翼云服务器一键部署脚本 (Nginx配置修复版)
# 完全修复Nginx配置问题

echo "=========================================="
echo " 天翼云服务器部署脚本 - Nginx配置修复版 "
echo "=========================================="

# 添加APT镜像源
cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/debian/ bullseye main non-free contrib
deb-src https://mirrors.aliyun.com/debian/ bullseye main non-free contrib
deb https://mirrors.aliyun.com/debian-security/ bullseye-security main
deb-src https://mirrors.aliyun.com/debian-security/ bullseye-security main
EOF

echo "更新软件包列表..."
apt update
echo "安装必要组件..."
apt install -y --no-install-recommends \
    curl wget openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq iptables-persistent netcat-openbsd nginx-extras

# 下载 Xray 核心 (多镜像源加速)
echo "下载Xray核心..."
ARCH=$(uname -m)
case $ARCH in
    "x86_64") ARCH="64" ;;
    "aarch64") ARCH="arm64-v8a" ;;
    *) ARCH="64" ;;  # 默认为64位
esac

# 多个镜像源列表
MIRRORS=(
    "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-$ARCH.zip"
    "https://hub.fastgit.xyz/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-$ARCH.zip"
    "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-$ARCH.zip"
)

# 尝试多个镜像下载
DOWNLOAD_SUCCESS=false
for mirror in "${MIRRORS[@]}"; do
    echo "尝试从镜像源下载: $mirror"
    if curl -L -o xray.zip "$mirror" --connect-timeout 30; then
        echo "下载成功!"
        DOWNLOAD_SUCCESS=true
        break
    else
        echo "当前镜像源下载失败，尝试下一个..."
    fi
    sleep 1
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
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
PUBLIC_PORT="8446"          # Nginx对外监听8446端口

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

# 修复Nginx配置
echo "修复Nginx配置..."
# 完全重写Nginx配置文件
cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

# 最重要的修复：正确放置stream块位置
stream {
    server {
        listen PUBLIC_PORT;
        proxy_pass 127.0.0.1:SERVER_PORT;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
        proxy_buffer_size 16k;
    }
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    sendfile on;
    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# 替换占位符
sed -i "s/PUBLIC_PORT/$PUBLIC_PORT/g" /etc/nginx/nginx.conf
sed -i "s/SERVER_PORT/$SERVER_PORT/g" /etc/nginx/nginx.conf

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
systemctl restart nginx >/dev/null 2>&1
sleep 2

# 检查服务状态
XRAY_STATUS=$(systemctl is-active xray)
NGINX_STATUS=$(systemctl is-active nginx)

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
echo " 关键服务状态:"
echo " Xray状态: $XRAY_STATUS"
echo " Nginx状态: $NGINX_STATUS"
echo " 防火墙状态:"
iptables -L -n -v | head -n 15
echo " 测试本地连接: nc -zv 127.0.0.1 $SERVER_PORT"
echo " 测试Nginx连接: nc -zv 127.0.0.1 $PUBLIC_PORT"
echo " 安全组: 确保开放 $PUBLIC_PORT 端口 TCP"
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
echo "1. 检查Xray监听:"
ss -tuln | grep $SERVER_PORT
echo ""
echo "2. 检查Nginx监听:"
ss -tuln | grep $PUBLIC_PORT
echo ""
echo "3. 测试本地连接:"
nc -zv 127.0.0.1 $SERVER_PORT
echo ""
echo "4. 测试Nginx转发:"
nc -zv 127.0.0.1 $PUBLIC_PORT
echo ""

# 最终验证
echo "最终验证:"
if ss -tuln | grep -q ":$PUBLIC_PORT"; then
    echo "✅ Nginx已在$PUBLIC_PORT端口监听"
else
    echo "❌ Nginx未在$PUBLIC_PORT端口监听，请检查Nginx配置"
    echo "查看Nginx错误日志: journalctl -u nginx -b --no-pager"
fi

# 如果Nginx启动失败，显示错误日志
if [ "$NGINX_STATUS" != "active" ]; then
    echo "Nginx服务启动失败，查看日志:"
    journalctl -u nginx --no-pager -n 20
else
    echo "✅ Nginx服务已成功启动"
fi

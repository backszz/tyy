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
    "https://raw.githubusercontent.com/XTLS/Xray-core/main/release/Xray-linux-$ARCH.zip"
    "https://cdn.jsdelivr.net/gh/XTLS/Xray-core@main/release/Xray-linux-$ARCH.zip"
    "https://raw.fastgit.org/XTLS/Xray-core/main/release/Xray-linux-$ARCH.zip"
    "https://raw.statically.io/XTLS/Xray-core/main/release/Xray-linux-$ARCH.zip"
    "https://raw.sevencdn.com/XTLS/Xray-core/main/release/Xray-linux-$ARCH.zip"
)

# 尝试多个镜像下载
DOWNLOAD_SUCCESS=false
for mirror in "${MIRRORS[@]}"; do
    echo "尝试从镜像源下载: $mirror"
    if curl -L -o xray.zip "$mirror" --connect-timeout 10 --retry 3 --retry-delay 2 --retry-max-time 30; then
        echo "下载成功!"
        DOWNLOAD_SUCCESS=true
        break
    else
        echo "当前镜像源下载失败，尝试下一个..."
        sleep 1
    fi
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "错误：无法下载Xray核心，请尝试以下方法："
    echo "1. 手动下载Xray核心："
    echo "   wget https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-$ARCH.zip"
    echo "2. 或者使用国内镜像："
    echo "   wget https://hub.fastgit.xyz/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-$ARCH.zip"
    echo "3. 如果以上方法都失败，请访问以下地址手动下载："
    echo "   https://github.com/XTLS/Xray-core/releases/tag/v1.8.4"
    echo "   下载后上传到服务器，然后继续运行脚本"
    exit 1
fi

# 验证下载的文件
if [ ! -f xray.zip ]; then
    echo "错误：下载文件不存在"
    exit 1
fi

# 检查文件大小
FILE_SIZE=$(stat -c%s xray.zip)
if [ "$FILE_SIZE" -lt 1000000 ]; then
    echo "错误：下载的文件可能不完整，请重试"
    rm -f xray.zip
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
SERVER_PORT="8446"          # Xray监听8446端口
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
cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

stream {
    server {
        listen $PUBLIC_PORT reuseport;
        proxy_pass 127.0.0.1:$SERVER_PORT;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
        proxy_buffer_size 16k;
        proxy_protocol on;
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
echo " 服务状态:"
echo " Xray状态: $XRAY_STATUS"
echo " Nginx状态: $NGINX_STATUS"
echo ""
echo " 测试连接: nc -zv localhost $PUBLIC_PORT"
echo " 重启服务: systemctl restart xray nginx"
echo "=========================================================="

# 保存客户端配置到文件
cat > client_config.txt <<EOF
天翼云服务器配置:
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

echo "客户端配置已保存到: client_config.txt"

# 生成二维码
echo "生成二维码配置..."
cat > client_config.json <<EOF
{
  "v": "2",
  "ps": "天翼云节点",
  "add": "$PUBLIC_IP",
  "port": "$PUBLIC_PORT",
  "id": "$UUID",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "reality",
  "sni": "$TARGET_DOMAIN",
  "alpn": "",
  "fp": "chrome",
  "pbk": "$PUBLIC_KEY",
  "sid": "$SHORT_ID",
  "flow": "xtls-rprx-vision"
}
EOF

echo ""
echo "二维码配置:"
qrencode -t ANSIUTF8 -l H < client_config.json
echo ""

# 生成分享链接
SHARE_LINK="vless://$UUID@$PUBLIC_IP:$PUBLIC_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$TARGET_DOMAIN&sid=$SHORT_ID#天翼云节点"
echo "分享链接:"
echo "$SHARE_LINK"
echo "=========================================================="

# 测试服务
echo "正在测试服务..."
echo "1. 测试Xray服务:"
systemctl status xray | head -n 10
echo ""
echo "2. 测试Nginx服务:"
systemctl status nginx | head -n 10
echo ""
echo "3. 测试端口监听:"
netstat -tulpn | grep -E "$PUBLIC_PORT|$SERVER_PORT"
echo ""
echo "4. 测试本地连接:"
nc -zv localhost $PUBLIC_PORT
echo ""
echo "5. 检查Nginx配置:"
nginx -t

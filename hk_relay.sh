#!/bin/bash

# 香港CN2中转服务器一键部署脚本 (8446端口版)

echo "=========================================="
echo " 香港CN2中转服务器部署脚本 - 8446端口版 "
echo "=========================================="
echo "正在安装必要组件..."

# 使用阿里云镜像源加速
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list

apt update
apt install -y --no-install-recommends \
    curl wget openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq iptables-persistent netcat-openbsd qrencode nginx-extras

# 输入后端服务器信息
echo ""
read -p "请输入天翼云服务器IP地址: " BACKEND_IP
BACKEND_PORT="8446"   # 天翼云Nginx监听8446端口
LOCAL_PORT="8443"    # 本地监听8443
TARGET_DOMAIN="www.qq.com"  # SNI域名

# 获取配置信息
echo ""
echo "请从天翼云服务器获取以下配置信息并输入:"
read -p "请输入天翼云服务器的UUID: " UUID
read -p "请输入天翼云服务器的Public Key: " PUBLIC_KEY
read -p "请输入天翼云服务器的Short ID: " SHORT_ID

# 配置Nginx转发
echo "配置Nginx转发规则..."
cat > /etc/nginx/conf.d/forward-proxy.conf <<EOF
events {
    worker_connections 1024;
}

stream {
    server {
        listen $LOCAL_PORT reuseport;
        proxy_pass $BACKEND_IP:$BACKEND_PORT;
        proxy_timeout 600s;
        proxy_connect_timeout 10s;
        proxy_buffer_size 16k;
    }
}
EOF

# 确保nginx.conf包含stream配置
if ! grep -q "include /etc/nginx/conf.d/*.conf;" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \\tinclude /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
fi

# 重启Nginx
echo "重启Nginx服务..."
systemctl restart nginx
systemctl enable nginx

# 获取公网IP（香港服务器）
echo "获取香港服务器公网IP..."
IP_SERVICES=(
    "ipinfo.io/ip"
    "ifconfig.me"
    "icanhazip.com"
    "api.ipify.org"
    "ip.seeip.org"
    "whatismyip.akamai.com"
)

# 尝试多个服务获取公网IP
for service in "${IP_SERVICES[@]}"; do
    PUBLIC_IP=$(curl -4s --connect-timeout 3 "$service")
    if [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    sleep 1
done

# 如果获取失败，使用默认方法
if [[ ! $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi

# 输出部署信息
clear
echo "=========================================================="
echo "                 香港中转服务器部署完成                     "
echo "                  监听端口: $LOCAL_PORT                     "
echo "=========================================================="
echo " 香港服务器IP: $PUBLIC_IP"
echo " 监听端口   : $LOCAL_PORT"
echo " 目标服务器 : $BACKEND_IP:$BACKEND_PORT"
echo "----------------------------------------------------------"
echo " 客户端配置:"
echo ""
echo " 地址: $PUBLIC_IP"
echo " 端口: $LOCAL_PORT"
echo " 用户ID: $UUID"
echo " 流控: xtls-rprx-vision"
echo " TLS类型: reality"
echo " Public Key: $PUBLIC_KEY"
echo " Short ID: $SHORT_ID"
echo " SNI: $TARGET_DOMAIN"
echo ""
echo "=========================================================="
echo " Nginx转发状态:"
systemctl status nginx | head -n 10
echo ""
echo " 测试连接: nc -zv $BACKEND_IP $BACKEND_PORT"
echo " 重启转发: systemctl restart nginx"
echo "=========================================================="

# 保存客户端配置到文件
cat > client_config.txt <<EOF
香港中转服务器配置 (Nginx转发):
------------------------------
地址: $PUBLIC_IP
端口: $LOCAL_PORT
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
  "ps": "香港中转节点(Nginx)",
  "add": "$PUBLIC_IP",
  "port": "$LOCAL_PORT",
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
SHARE_LINK="vless://$UUID@$PUBLIC_IP:$LOCAL_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$TARGET_DOMAIN&sid=$SHORT_ID#香港中转节点(Nginx)"
echo "分享链接:"
echo "$SHARE_LINK"
echo "=========================================================="

# 测试后端服务器连接
echo "正在测试后端服务器连接..."
echo "测试命令: nc -zv $BACKEND_IP $BACKEND_PORT"
if command -v nc &> /dev/null; then
    if nc -zv $BACKEND_IP $BACKEND_PORT; then
        echo "连接测试成功!"
    else
        echo "连接测试失败!"
        echo "请检查:"
        echo "1. 天翼云服务器是否运行正常"
        echo "2. 天翼云安全组是否开放 $BACKEND_PORT 端口"
        echo "3. 天翼云本地防火墙设置"
        echo "4. 网络路由是否有问题"
    fi
else
    echo "警告: nc 命令未安装，无法执行连接测试"
fi

# 补充诊断信息
echo ""
echo "补充诊断信息:"
echo "1. 验证网络连通性: ping -c 4 $BACKEND_IP"
ping -c 4 $BACKEND_IP
echo ""
echo "2. 验证端口连通性: timeout 3 telnet $BACKEND_IP $BACKEND_PORT"
timeout 3 telnet $BACKEND_IP $BACKEND_PORT
echo ""
echo "3. 检查Nginx状态: systemctl status nginx"
systemctl status nginx | head -n 20
echo ""
echo "4. 检查Nginx配置: nginx -t"
nginx -t

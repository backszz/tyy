#!/bin/bash

# 香港中转服务器一键部署脚本 (修复版2)
# 监听8443端口，转发到天翼云服务器的8443端口
# 修复IP获取问题，并提示输入配置信息

echo "=========================================="
echo " 香港中转服务器部署脚本 - 8443端口 (修复版) "
echo "=========================================="
echo "正在更新系统并安装必要组件..."

# 使用阿里云镜像源加速
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list

apt update
apt install -y --no-install-recommends \
    curl openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq ufw iptables-persistent

# 输入后端服务器信息
echo ""
read -p "请输入天翼云服务器IP地址: " BACKEND_IP
BACKEND_PORT="8443"  # 使用8443端口
LOCAL_PORT="8443"    # 本地监听8443端口
TARGET_DOMAIN="www.qq.com"  # SNI域名

# 提示用户输入天翼云服务器的配置信息
echo ""
echo "请从天翼云服务器部署脚本的输出中获取以下信息并输入:"
read -p "请输入天翼云服务器的UUID: " UUID
read -p "请输入天翼云服务器的Public Key: " PUBLIC_KEY
read -p "请输入天翼云服务器的Short ID: " SHORT_ID

# 配置NAT转发
echo "配置端口转发 ($LOCAL_PORT → $BACKEND_IP:$BACKEND_PORT)..."

# 清除旧规则
iptables -t nat -F
iptables -t nat -X

# 添加新规则
iptables -t nat -A PREROUTING -p tcp --dport $LOCAL_PORT -j DNAT --to-destination $BACKEND_IP:$BACKEND_PORT
iptables -t nat -A PREROUTING -p udp --dport $LOCAL_PORT -j DNAT --to-destination $BACKEND_IP:$BACKEND_PORT
iptables -t nat -A POSTROUTING -d $BACKEND_IP -p tcp --dport $BACKEND_PORT -j MASQUERADE
iptables -t nat -A POSTROUTING -d $BACKEND_IP -p udp --dport $BACKEND_PORT -j MASQUERADE

# 开启内核转发
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# 配置防火墙
echo "配置防火墙..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow $LOCAL_PORT/tcp >/dev/null 2>&1
ufw allow $LOCAL_PORT/udp >/dev/null 2>&1
echo "y" | ufw enable >/dev/null 2>&1

# 保存规则
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1

# 获取服务器公网IP（使用多个备用API）
get_public_ip() {
    # 尝试多个IP获取服务
    local ips
    ips=$(curl -4s --connect-timeout 5 \
        "https://api64.ipify.org?format=json" \
        "https://ipinfo.io/json" \
        "https://ifconfig.me/all.json" 2>/dev/null)
    local ip
    ip=$(echo "$ips" | jq -r '.ip' 2>/dev/null | head -1)
    if [ -z "$ip" ]; then
        ip=$(echo "$ips" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi
    echo "$ip"
}
PUBLIC_IP=$(get_public_ip)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="[服务器公网IP]"
    echo "警告：无法获取公网IP，请手动填写"
fi

# 输出部署信息
clear
echo "=========================================================="
echo "                 香港中转服务器部署完成                     "
echo "                  监听端口: $LOCAL_PORT                     "
echo "=========================================================="
echo " 服务器IP  : $PUBLIC_IP"
echo " 监听端口  : $LOCAL_PORT"
echo " 目标服务器: $BACKEND_IP:$BACKEND_PORT"
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
echo " 防火墙状态: $(ufw status | head -1)"
echo " 转发规则:"
iptables -t nat -L -n -v
echo ""
echo " 测试连接: nc -zv $BACKEND_IP $BACKEND_PORT"
echo " 重启转发: netfilter-persistent reload"
echo "=========================================================="

# 保存客户端配置到文件
cat > client_config.txt <<EOF
香港中转服务器配置:
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

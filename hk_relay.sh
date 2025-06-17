#!/bin/bash

# 香港中转服务器一键部署脚本
# 监听443端口，转发到天翼云服务器的8433端口

echo "=========================================="
echo " 香港中转服务器部署脚本 - 转发到8433端口 "
echo "=========================================="
echo "正在安装必要组件..."

# 使用阿里云镜像源加速
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list

apt update
apt install -y --no-install-recommends \
    curl openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq ufw

# 输入后端服务器信息
read -p "请输入后端服务器IP地址: " BACKEND_IP
BACKEND_PORT="8433"  # 使用8433端口
LOCAL_PORT="443"

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
sysctl -p

# 配置防火墙
echo "配置防火墙..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow $LOCAL_PORT/tcp
ufw allow $LOCAL_PORT/udp
echo "y" | ufw enable

# 保存规则
apt install -y iptables-persistent
netfilter-persistent save
netfilter-persistent reload

# 输出部署信息
clear
echo "=========================================================="
echo "                 香港中转服务器部署完成                     "
echo "=========================================================="
echo " 服务器IP  : $(curl -4s ifconfig.co)"
echo " 监听端口  : $LOCAL_PORT"
echo " 目标服务器: $BACKEND_IP:$BACKEND_PORT"
echo "----------------------------------------------------------"
echo " 客户端配置:"
echo ""
echo " 地址: [香港服务器IP]"
echo " 端口: $LOCAL_PORT"
echo " 用户ID: [使用天翼云服务器的UUID]"
echo " 流控: xtls-rprx-vision"
echo " TLS类型: reality"
echo " Public Key: [使用天翼云服务器的Public Key]"
echo " Short ID: [使用天翼云服务器的Short ID]"
echo " SNI: $TARGET_DOMAIN"
echo ""
echo "=========================================================="
echo " 调试命令:"
echo " 查看连接: netstat -tuln | grep $LOCAL_PORT"
echo " 查看转发: iptables -t nat -L -n -v"
echo " 重启服务: netfilter-persistent reload"
echo "=========================================================="

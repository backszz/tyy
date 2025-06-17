#!/bin/bash

# 香港中转服务器一键部署脚本（最终修复版）
# 完全修复IP获取问题，确保所有工具安装

echo "=========================================="
echo " 香港中转服务器部署脚本 - 最终修复版 "
echo "=========================================="
echo "正在安装必要组件..."

# 使用阿里云镜像源加速
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list

apt update
apt install -y --no-install-recommends \
    curl wget openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq iptables-persistent netcat

# 输入后端服务器信息
echo ""
read -p "请输入天翼云服务器IP地址: " BACKEND_IP
BACKEND_PORT="8443"  # 使用8443端口
LOCAL_PORT="8443"    # 本地监听8443端口
TARGET_DOMAIN="www.qq.com"  # SNI域名

# 获取配置信息
echo ""
echo "正在获取配置信息..."
UUID="72505435-4bd8-4eb4-9a63-04a818e57d43"
PUBLIC_KEY="cujdBC0t8jmfzUNwdCtCZhk3UBML_RWeN1vUq-dWyDM"
SHORT_ID="4384eb8ebcc40a60"

# 配置NAT转发
echo ""
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

# 保存规则
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1

# 正确获取香港服务器公网IP
echo "获取香港服务器公网IP..."
IP_SERVICES=(
    "ipinfo.io/ip"
    "ifconfig.co"
    "icanhazip.com"
    "api.ipify.org"
    "ip.seeip.org"
)

for service in "${IP_SERVICES[@]}"; do
    PUBLIC_IP=$(curl -4s --connect-timeout 3 "$service")
    if [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$PUBLIC_IP" != "$BACKEND_IP" ]; then
        break
    fi
    sleep 1
done

# 如果仍然失败，使用最后一招
if [[ ! $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    PUBLIC_IP=$(curl -4s http://whatismyip.akamai.com/)
fi

# 确保IP不是后端IP
if [ "$PUBLIC_IP" == "$BACKEND_IP" ] || [ -z "$PUBLIC_IP" ]; then
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
echo " 转发规则:"
iptables -t nat -L -n -v
echo ""
echo " 测试连接: nc -zv $BACKEND_IP $BACKEND_PORT"
echo " 重启转发: netfilter-persistent reload"
echo "=========================================================="

# 生成二维码
echo "生成二维码配置..."
cat > client_config.json <<EOF
{
  "v": "2",
  "ps": "香港中转节点",
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

# 安装qrencode并生成二维码
if ! command -v qrencode &> /dev/null; then
    echo "正在安装qrencode..."
    apt install -y qrencode
fi

echo ""
echo "二维码配置:"
qrencode -t ANSIUTF8 -l H < client_config.json
echo ""

# 生成分享链接
SHARE_LINK="vless://$UUID@$PUBLIC_IP:$LOCAL_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$TARGET_DOMAIN&sid=$SHORT_ID#香港中转节点"
echo "分享链接:"
echo "$SHARE_LINK"
echo "=========================================================="

# 测试后端服务器连接
echo "正在测试后端服务器连接..."
if timeout 5 nc -zv $BACKEND_IP $BACKEND_PORT; then
    echo "连接测试成功!"
else
    echo "连接测试失败!"
    echo "请检查:"
    echo "1. 天翼云服务器是否运行正常"
    echo "2. 天翼云安全组是否开放 $BACKEND_PORT 端口"
    echo "3. 天翼云本地防火墙设置"
    echo ""
    echo "快速诊断:"
    echo "  在天翼云服务器执行: nc -lvvp $BACKEND_PORT"
    echo "  然后在香港服务器执行: nc -zv $BACKEND_IP $BACKEND_PORT"
fi

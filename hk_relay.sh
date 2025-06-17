#!/bin/bash

# 香港中转服务器一键部署脚本（最终修复版）
# 监听8443端口，转发到天翼云服务器的8443端口
# 完全修复IP显示问题，移除ufw依赖，优化错误处理

echo "=========================================="
echo " 香港中转服务器部署脚本 - 最终版 "
echo "=========================================="
echo "正在更新系统并安装必要组件..."

# 使用阿里云镜像源加速
sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
sed -i 's|security.debian.org|mirrors.aliyun.com/debian-security|g' /etc/apt/sources.list

apt update
apt install -y --no-install-recommends \
    curl wget openssl uuid-runtime ca-certificates net-tools \
    iproute2 iptables unzip jq iptables-persistent

# 输入后端服务器信息
echo ""
read -p "请输入天翼云服务器IP地址: " BACKEND_IP
BACKEND_PORT="8443"  # 使用8443端口
LOCAL_PORT="8443"    # 本地监听8443端口
TARGET_DOMAIN="www.qq.com"  # SNI域名

# 从天翼云服务器获取配置信息
echo ""
echo "正在从天翼云服务器获取配置信息..."
UUID=""
PUBLIC_KEY=""
SHORT_ID=""

# 尝试从服务器获取信息
if command -v ssh >/dev/null 2>&1; then
    for i in {1..2}; do
        echo "尝试 $i/2 获取配置..."
        
        # 尝试通过SSH获取配置信息
        CONFIG_INFO=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$BACKEND_IP \
            "grep -E 'id|publicKey|shortIds' /usr/local/etc/xray/config.json 2>/dev/null" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$CONFIG_INFO" ]; then
            UUID=$(echo "$CONFIG_INFO" | grep '"id"' | awk -F'"' '{print $4}')
            PUBLIC_KEY=$(echo "$CONFIG_INFO" | grep '"publicKey"' | awk -F'"' '{print $4}')
            SHORT_ID=$(echo "$CONFIG_INFO" | grep '"shortIds"' | awk -F'[' '{print $2}' | awk -F']' '{print $1}' | tr -d '" ')
            break
        else
            sleep 2
        fi
    done
fi

# 如果自动获取失败，提示手动输入
if [ -z "$UUID" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
    echo "警告：无法自动获取配置信息，请手动输入"
    read -p "请输入天翼云服务器的UUID: " UUID
    read -p "请输入天翼云服务器的Public Key: " PUBLIC_KEY
    read -p "请输入天翼云服务器的Short ID: " SHORT_ID
fi

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

# 获取服务器公网IP (多种方法尝试)
get_public_ip() {
    local ips=()
    local services=(
        "ipinfo.io/ip"
        "ifconfig.me"
        "icanhazip.com"
        "api.ipify.org"
        "ip.seeip.org"
    )
    
    # 尝试多个服务
    for service in "${services[@]}"; do
        ip=$(curl -4s --connect-timeout 3 "$service" 2>/dev/null)
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ips+=("$ip")
            # 如果已经收集到3个相同的IP，直接返回
            if [ "$(printf '%s\n' "${ips[@]}" | grep -c "$ip")" -ge 3 ]; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    # 返回最常见的IP
    if [ "${#ips[@]}" -gt 0 ]; then
        printf '%s\n' "${ips[@]}" | sort | uniq -c | sort -nr | head -1 | awk '{print $2}'
        return 0
    fi
    
    # 最后尝试本地IP
    local local_ip=$(hostname -I | awk '{print $1}')
    if [[ "$local_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$local_ip"
    else
        echo "无法获取公网IP"
    fi
}

PUBLIC_IP=$(get_public_ip)

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

# 测试后端服务器连接
echo ""
echo "正在测试后端服务器连接..."
CONNECTION_RESULT=$(timeout 5 nc -zv $BACKEND_IP $BACKEND_PORT 2>&1)
if [ $? -eq 0 ]; then
    echo "连接测试成功: $CONNECTION_RESULT"
else
    echo "连接测试失败: $CONNECTION_RESULT"
    echo "请检查:"
    echo "1. 天翼云服务器是否运行正常"
    echo "2. 天翼云安全组是否开放 $BACKEND_PORT 端口"
    echo "3. 天翼云本地防火墙设置"
fi

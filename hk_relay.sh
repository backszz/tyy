#!/bin/bash
# 香港CN2 GIA中转服务器部署脚本
# 保存到: https://raw.githubusercontent.com/backszz/tyy/main/hk_relay.sh

# 配置参数
CHINA_PORT="443"           # 固定端口
LOCAL_PORT="443"           # 监听443端口
RELAY_IP=$(curl -4s ifconfig.co)  # 获取香港服务器IP

# 用户输入
read -p "请输入国内服务器IP: " CHINA_IP
read -p "请输入UUID: " UUID
read -p "请输入Public Key: " PUBLIC_KEY
read -p "请输入Short ID: " SHORT_ID
read -p "请输入伪装目标域名(如www.bing.com): " TARGET_DOMAIN

# 安装必要组件
echo "正在安装必要组件..."
apt update
apt install -y iptables-persistent netfilter-persistent qrencode jq

# 配置端口转发
echo "配置端口转发规则..."
iptables -t nat -A PREROUTING -p tcp --dport $LOCAL_PORT -j DNAT --to-destination $CHINA_IP:$CHINA_PORT
iptables -t nat -A PREROUTING -p udp --dport $LOCAL_PORT -j DNAT --to-destination $CHINA_IP:$CHINA_PORT
iptables -t nat -A POSTROUTING -d $CHINA_IP -p tcp --dport $CHINA_PORT -j MASQUERADE
iptables -t nat -A POSTROUTING -d $CHINA_IP -p udp --dport $CHINA_PORT -j MASQUERADE

# 保存防火墙规则
netfilter-persistent save
netfilter-persistent reload

# 启用IP转发
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 配置BBR加速
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

# 开放中转端口
ufw allow $LOCAL_PORT/tcp
ufw allow $LOCAL_PORT/udp
ufw reload

# 生成VLESS链接
VLESS_LINK="vless://$UUID@$RELAY_IP:$LOCAL_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&sni=$TARGET_DOMAIN&type=tcp&flow=xtls-rprx-vision#香港CN2中转"

# 生成二维码
echo "生成客户端二维码..."
echo "$VLESS_LINK" | qrencode -o /root/hk_client.png -t png

# 创建客户端配置页面
HTML_PATH="/var/www/html/index.html"
apt install -y nginx
cat > $HTML_PATH <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>香港CN2回国节点</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: auto; padding: 20px; }
        .card { border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin: 20px 0; }
        h2 { color: #1a73e8; }
        img { max-width: 100%; }
        .config { background: #f8f9fa; padding: 15px; border-radius: 6px; font-family: monospace; word-wrap: break-word; }
    </style>
</head>
<body>
    <h1>香港CN2回国节点配置</h1>
    
    <div class="card">
        <h2>扫码配置</h2>
        <img src="hk_client.png" alt="客户端二维码">
        <p>使用V2rayN/V2rayNG扫描二维码</p>
    </div>
    
    <div class="card">
        <h2>手动配置</h2>
        <div class="config">
            <p>地址: $RELAY_IP</p>
            <p>端口: $LOCAL_PORT</p>
            <p>用户ID: $UUID</p>
            <p>流控: xtls-rprx-vision</p>
            <p>TLS: reality</p>
            <p>Public Key: $PUBLIC_KEY</p>
            <p>Short ID: $SHORT_ID</p>
            <p>SNI: $TARGET_DOMAIN</p>
        </div>
    </div>
    
    <div class="card">
        <h2>技术支持</h2>
        <p>部署时间: $(date)</p>
        <p>服务器状态: <span style="color:green">●</span> 在线</p>
    </div>
</body>
</html>
EOF

# 复制二维码到网站目录
cp /root/hk_client.png /var/www/html/

# 重启nginx
systemctl restart nginx

# 输出信息
clear
echo "=============================================="
echo "  香港中转服务器部署成功！"
echo "  服务器IP: $RELAY_IP"
echo "  监听端口: $LOCAL_PORT"
echo "  目标服务器: $CHINA_IP:$CHINA_PORT"
echo "=============================================="
echo "  客户端配置页面: http://$RELAY_IP/"
echo "=============================================="
echo "  手动配置信息:"
echo "  地址: $RELAY_IP"
echo "  端口: $LOCAL_PORT"
echo "  用户ID: $UUID"
echo "  流控: xtls-rprx-vision"
echo "  Public Key: $PUBLIC_KEY"
echo "  Short ID: $SHORT_ID"
echo "  SNI: $TARGET_DOMAIN"
echo "=============================================="

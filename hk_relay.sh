#!/bin/bash

# 香港中转服务器一键部署脚本
# 固定端口：443 → 后端服务器443

echo "================================"
echo " 香港中转服务器部署脚本 "
echo "================================"
echo "正在更新系统并安装必要组件..."

# 使用阿里云镜像源
cat > /etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/debian/ bookworm main non-free non-free-firmware contrib
deb-src http://mirrors.aliyun.com/debian/ bookworm main non-free non-free-firmware contrib

deb http://mirrors.aliyun.com/debian-security/ bookworm-security main non-free non-free-firmware contrib
deb-src http://mirrors.aliyun.com/debian-security/ bookworm-security main non-free non-free-firmware contrib

deb http://mirrors.aliyun.com/debian/ bookworm-updates main non-free non-free-firmware contrib
deb-src http://mirrors.aliyun.com/debian/ bookworm-updates main non-free non-free-firmware contrib

deb http://mirrors.aliyun.com/debian/ bookworm-backports main non-free non-free-firmware contrib
deb-src http://mirrors.aliyun.com/debian/ bookworm-backports main non-free non-free-firmware contrib
EOF

# 更新系统
apt update
apt upgrade -y
apt autoremove -y

# 安装必要组件
apt install -y --no-install-recommends \
    curl wget net-tools iproute2 iptables ufw nginx qrencode

# 获取后端服务器信息
read -p "请输入天翼云服务器IP地址: " BACKEND_IP
BACKEND_PORT="443"
LOCAL_PORT="443"

# 配置NAT转发
echo "配置NAT转发规则..."
iptables -t nat -F
iptables -t nat -X

# TCP转发
iptables -t nat -A PREROUTING -p tcp --dport $LOCAL_PORT -j DNAT --to-destination $BACKEND_IP:$BACKEND_PORT
iptables -t nat -A POSTROUTING -d $BACKEND_IP -p tcp --dport $BACKEND_PORT -j MASQUERADE

# UDP转发
iptables -t nat -A PREROUTING -p udp --dport $LOCAL_PORT -j DNAT --to-destination $BACKEND_IP:$BACKEND_PORT
iptables -t nat -A POSTROUTING -d $BACKEND_IP -p udp --dport $BACKEND_PORT -j MASQUERADE

# 开启内核转发
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 保存iptables规则
apt install -y iptables-persistent
netfilter-persistent save
netfilter-persistent reload

# 配置防火墙
echo "配置防火墙..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow $LOCAL_PORT/tcp
ufw allow $LOCAL_PORT/udp
echo "y" | ufw enable
ufw reload

# 创建客户端配置页面
echo "创建客户端配置页面..."
mkdir -p /var/www/html
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>香港中转节点配置</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        h1, h2 { color: #2c3e50; text-align: center; }
        .config-box { background: #f9f9f9; border-radius: 8px; padding: 20px; margin: 20px 0; }
        .param { font-weight: bold; }
        .value { font-family: monospace; background: #eee; padding: 2px 5px; border-radius: 3px; }
        .qr-code { text-align: center; margin: 20px 0; }
        .note { color: #e74c3c; padding: 10px; background: #fdeded; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>香港中转节点配置</h1>
    <div class="note">
        <p>以下配置参数需要从<span class="param">天翼云服务器</span>获取：</p>
        <p>UUID、Public Key、Short ID</p>
    </div>
    
    <div class="config-box">
        <h2>手动配置参数</h2>
        <p><span class="param">地址:</span> <span class="value">REPLACE_SERVER_IP</span></p>
        <p><span class="param">端口:</span> <span class="value">443</span></p>
        <p><span class="param">用户ID (UUID):</span> <span class="value">从天翼云服务器获取</span></p>
        <p><span class="param">流控:</span> <span class="value">xtls-rprx-vision</span></p>
        <p><span class="param">Public Key:</span> <span class="value">从天翼云服务器获取</span></p>
        <p><span class="param">Short ID:</span> <span class="value">从天翼云服务器获取</span></p>
        <p><span class="param">SNI:</span> <span class="value">www.bing.com</span></p>
    </div>
    
    <div class="qr-code">
        <h2>配置二维码</h2>
        <img id="qr-img" src="" alt="配置二维码">
        <p>请在天翼云服务器部署后获取配置链接</p>
    </div>

    <script>
        // 自动获取服务器IP
        document.querySelector('.value').textContent = window.location.hostname;
        
        // 更新所有IP显示
        document.querySelectorAll('.value').forEach(el => {
            if (el.textContent === 'REPLACE_SERVER_IP') {
                el.textContent = window.location.hostname;
            }
        });
    </script>
</body>
</html>
EOF

# 重启Nginx
systemctl restart nginx

# 输出部署信息
clear
SERVER_IP=$(curl -4s ifconfig.co)
echo "=========================================================="
echo "                 香港中转服务器部署完成                   "
echo "=========================================================="
echo " 服务器IP  : $SERVER_IP"
echo " 监听端口  : $LOCAL_PORT"
echo " 目标服务器: $BACKEND_IP:$BACKEND_PORT"
echo "=========================================================="
echo " 客户端配置页面: http://$SERVER_IP/"
echo "=========================================================="
echo " 调试命令:"
echo " 查看连接: netstat -tuln | grep $LOCAL_PORT"
echo " 查看NAT规则: iptables -t nat -L -n -v"
echo " 测试转发: curl -I http://$SERVER_IP/"
echo "=========================================================="

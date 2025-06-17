#!/bin/bash
# 香港CN2 GIA中转服务器部署脚本 (修复IP获取问题)
# 保存到: https://raw.githubusercontent.com/backszz/tyy/main/hk_relay_fixed_ip.sh

# 配置参数
CHINA_PORT="443"           # 固定端口
LOCAL_PORT="443"           # 监听443端口

# 获取公网IP (使用多个备用服务)
fetch_ip() {
    # 尝试多个IP获取服务
    ip1=$(curl -4s --max-time 10 ifconfig.io 2>/dev/null)
    ip2=$(curl -4s --max-time 10 icanhazip.com 2>/dev/null)
    ip3=$(curl -4s --max-time 10 ident.me 2>/dev/null)
    
    # 验证IP格式
    for ip in $ip1 $ip2 $ip3; do
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return
        fi
    done
    
    # 如果都失败，尝试从系统接口获取
    sys_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
    if [[ $sys_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$sys_ip"
    else
        echo "IP获取失败"
    fi
}

RELAY_IP=$(fetch_ip)

# 用户输入
read -p "请输入国内服务器IP: " CHINA_IP
read -p "请输入UUID: " UUID
read -p "请输入Public Key: " PUBLIC_KEY
read -p "请输入Short ID: " SHORT_ID
read -p "请输入伪装目标域名(如www.bing.com): " TARGET_DOMAIN

# 安装必要组件
echo "正在安装必要组件..."
apt update
apt install -y iptables-persistent netfilter-persistent qrencode jq nginx

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
echo "启用IP转发..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 配置BBR加速
echo "配置BBR加速..."
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

# 开放中转端口
ufw allow $LOCAL_PORT/tcp
ufw allow $LOCAL_PORT/udp
sudo ufw --force enable
sudo ufw reload

# 生成VLESS链接
VLESS_LINK="vless://$UUID@$RELAY_IP:$LOCAL_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&sni=$TARGET_DOMAIN&type=tcp&flow=xtls-rprx-vision#香港CN2中转"

# 生成二维码
echo "生成客户端二维码..."
echo "$VLESS_LINK" | qrencode -o /var/www/html/hk_client.png -t png

# 创建客户端配置页面
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>香港CN2回国节点</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f7fa;
            color: #333;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 0 20px rgba(0, 0, 0, 0.1);
        }
        header {
            text-align: center;
            margin-bottom: 30px;
            border-bottom: 1px solid #eee;
            padding-bottom: 20px;
        }
        h1 {
            color: #1a73e8;
            margin: 0;
        }
        .card {
            background: #fff;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 25px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05);
            border: 1px solid #e0e0e0;
        }
        h2 {
            color: #1a73e8;
            margin-top: 0;
            font-size: 1.5em;
        }
        .qr-container {
            text-align: center;
            margin: 20px 0;
        }
        .qr-container img {
            max-width: 250px;
            border: 1px solid #ddd;
            border-radius: 8px;
            padding: 10px;
        }
        .config-details {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 6px;
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 0.95em;
            overflow-x: auto;
        }
        .config-item {
            margin-bottom: 8px;
        }
        .status-container {
            display: flex;
            justify-content: space-around;
            text-align: center;
            flex-wrap: wrap;
        }
        .status-item {
            flex: 1;
            min-width: 150px;
            padding: 10px;
        }
        .status-value {
            font-size: 1.2em;
            font-weight: bold;
            color: #1a73e8;
        }
        .online-status {
            display: inline-block;
            width: 12px;
            height: 12px;
            background-color: #4caf50;
            border-radius: 50%;
            margin-right: 5px;
            animation: pulse 1.5s infinite;
        }
        @keyframes pulse {
            0% { opacity: 0.7; }
            50% { opacity: 1; }
            100% { opacity: 0.7; }
        }
        footer {
            text-align: center;
            margin-top: 25px;
            color: #666;
            font-size: 0.9em;
        }
        .btn {
            display: inline-block;
            background: #1a73e8;
            color: white;
            padding: 10px 20px;
            border-radius: 5px;
            text-decoration: none;
            margin: 10px 0;
            font-weight: bold;
            transition: background 0.3s;
        }
        .btn:hover {
            background: #0d5bba;
        }
        @media (max-width: 600px) {
            .container {
                padding: 15px;
            }
            .status-container {
                flex-direction: column;
            }
        }
    </style>
</head>
<body>
<div class="container">
    <header>
        <h1>香港CN2回国节点</h1>
        <p>高速稳定连接国内资源</p>
    </header>
    
    <div class="card">
        <h2>扫码配置</h2>
        <div class="qr-container">
            <img src="hk_client.png" alt="客户端二维码">
        </div>
        <p style="text-align: center;">使用 V2rayN/V2rayNG 扫描二维码</p>
        <p style="text-align: center;">
            <a href="https://github.com/2dust/v2rayN/releases" class="btn" target="_blank">下载Windows客户端</a>
            <a href="https://github.com/2dust/v2rayNG/releases" class="btn" target="_blank">下载Android客户端</a>
        </p>
    </div>
    
    <div class="card">
        <h2>手动配置参数</h2>
        <div class="config-details">
            <div class="config-item"><strong>地址:</strong> $RELAY_IP</div>
            <div class="config-item"><strong>端口:</strong> $LOCAL_PORT</div>
            <div class="config-item"><strong>用户ID:</strong> $UUID</div>
            <div class="config-item"><strong>流控:</strong> xtls-rprx-vision</div>
            <div class="config-item"><strong>TLS:</strong> reality</div>
            <div class="config-item"><strong>Public Key:</strong> $PUBLIC_KEY</div>
            <div class="config-item"><strong>Short ID:</strong> $SHORT_ID</div>
            <div class="config-item"><strong>SNI:</strong> $TARGET_DOMAIN</div>
        </div>
    </div>
    
    <div class="card">
        <h2>节点状态</h2>
        <div class="status-container">
            <div class="status-item">
                <div>服务状态</div>
                <div class="status-value"><span class="online-status"></span> 在线</div>
            </div>
            <div class="status-item">
                <div>部署时间</div>
                <div class="status-value">$(date +"%Y-%m-%d")</div>
            </div>
            <div class="status-item">
                <div>服务器位置</div>
                <div class="status-value">香港CN2 GIA</div>
            </div>
            <div class="status-item">
                <div>后端服务器</div>
                <div class="status-value">天翼云</div>
            </div>
        </div>
    </div>
    
    <footer>
        <p>部署时间: $(date +"%Y-%m-%d %H:%M:%S")</p>
        <p>© 2023 回国加速节点 | 技术支持: admin@yourdomain.com</p>
    </footer>
</div>

<script>
    // 更新时间显示
    function updateTime() {
        const now = new Date();
        const timeString = now.toLocaleTimeString();
        const dateString = now.toLocaleDateString();
        document.querySelector('footer p:first-child').textContent = 
            '最后更新: ' + dateString + ' ' + timeString;
    }
    
    setInterval(updateTime, 1000);
    updateTime();
</script>
</body>
</html>
EOF

# 重启Nginx
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

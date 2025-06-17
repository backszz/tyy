#!/bin/bash
# 中转服务器部署脚本（动态端口转发）
# 执行: wget -O relay.sh https://raw.githubusercontent.com/yourrepo/relay.sh && bash relay.sh

# 获取配置参数
read -p "请输入国内服务器IP: " CHINA_IP
read -p "请输入Reality端口 (默认443): " CHINA_PORT
CHINA_PORT=${CHINA_PORT:-443}

# 安装必要组件
echo ""
echo "正在安装必要组件..."
sleep 2
apt update
apt install -y iptables-persistent netfilter-persistent cron

# 启用IP转发
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 随机端口生成函数
generate_random_port() {
  echo $(( RANDOM % 40000 + 10000 ))
}

# 初始随机端口
INITIAL_PORT=$(generate_random_port)

# 配置端口转发
echo ""
echo "配置端口转发规则..."
sleep 2
iptables -t nat -A PREROUTING -p tcp --dport $INITIAL_PORT -j DNAT --to-destination $CHINA_IP:$CHINA_PORT
iptables -t nat -A POSTROUTING -d $CHINA_IP -p tcp --dport $CHINA_PORT -j MASQUERADE

# 保存防火墙规则
netfilter-persistent save
netfilter-persistent reload

# 每日更换端口脚本
echo ""
echo "设置端口随机化..."
sleep 2
cat > /usr/local/bin/update_port.sh <<EOF
#!/bin/bash
# 获取当前转发端口
CURRENT_PORT=\$(iptables -t nat -L PREROUTING -n -v --line-numbers | grep DNAT | grep "dpt" | awk '{print \$16}' | cut -d: -f2 | head -1)

# 生成新端口（确保不同于当前端口）
while true; do
  NEW_PORT=\$(generate_random_port)
  [ "\$NEW_PORT" != "\$CURRENT_PORT" ] && break
done

# 清理旧规则
RULE_NUM=\$(iptables -t nat -L PREROUTING -n -v --line-numbers | grep DNAT | grep "dpt:\$CURRENT_PORT" | awk '{print \$1}' | head -1)
if [ -n "\$RULE_NUM" ]; then
  iptables -t nat -D PREROUTING \$RULE_NUM
fi

# 添加新规则
iptables -t nat -A PREROUTING -p tcp --dport \$NEW_PORT -j DNAT --to-destination $CHINA_IP:$CHINA_PORT
netfilter-persistent save

# 更新防火墙
ufw delete allow \$CURRENT_PORT/tcp >/dev/null 2>&1
ufw allow \$NEW_PORT/tcp
ufw reload

# 输出信息
echo "\$(date) 端口更换完成: \$CURRENT_PORT → \$NEW_PORT"
EOF

chmod +x /usr/local/bin/update_port.sh
chmod +x /usr/bin/generate_random_port  # 确保函数可用

# 添加到定时任务（每天3点更换）
crontab -l > mycron
echo "0 3 * * * /usr/local/bin/update_port.sh" >> mycron
crontab mycron
rm mycron

# 安装监控工具
echo ""
echo "安装网络监控工具..."
sleep 2
apt install -y iftop

# 流量混淆（伪网站）
echo ""
echo "设置流量混淆伪装..."
sleep 2
apt install -y nginx
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<title>Maintenance Page</title>
</head>
<body>
<h1>Server Maintenance</h1>
<p>This server is currently undergoing maintenance. Please check back later.</p>
</body>
</html>
EOF

# 创建监控脚本
cat > /usr/local/bin/monitor.sh <<'EOF'
#!/bin/bash
echo "=============================="
echo "  中转服务器实时状态"
echo "  当前监听端口: $(iptables -t nat -L PREROUTING -n | grep DNAT | awk '{print $11}' | cut -d: -f2)"
echo "  目标服务器: $CHINA_IP:$CHINA_PORT"
echo "=============================="
echo "  当前连接数: $(netstat -an | grep ESTAB | awk '{print $4}' | grep $(iptables -t nat -L PREROUTING -n | grep DNAT | awk '{print $11}' | cut -d: -f2) | wc -l)"
echo "  今日流量统计:"
iftop -t -s 10 -L 50 -n -N -P -o "source" -f "dst host $CHINA_IP"
echo "=============================="
EOF
chmod +x /usr/local/bin/monitor.sh

# 首次执行端口更新
/usr/local/bin/update_port.sh

# 清理痕迹
history -c

# 输出信息
clear
CURRENT_PORT=$(iptables -t nat -L PREROUTING -n -v --line-numbers | grep DNAT | grep "dpt" | awk '{print $16}' | cut -d: -f2 | head -1)
echo "=============================================="
echo "  中转服务器部署成功！"
echo "  服务器IP: $(curl -4s ifconfig.co)"
echo "  当前监听端口: $CURRENT_PORT"
echo "  目标服务器: $CHINA_IP:$CHINA_PORT"
echo "=============================================="
echo "  重要信息："
echo "  1. 监听端口每天凌晨3点自动更换"
echo "  2. 查看实时状态: /usr/local/bin/monitor.sh"
echo "  3. 伪装网站: http://$(curl -4s ifconfig.co)/"
echo "=============================================="
echo "  客户端连接配置："
echo "  地址: [本服务器IP]"
echo "  端口: $CURRENT_PORT (每日自动更换)"
echo "  用户ID: [国内服务器UUID]"
echo "  流控: xtls-rprx-vision"
echo "  TLS: reality"
echo "  Public Key: [国内服务器公钥]"
echo "  Short ID: [国内服务器短ID]"
echo "  SNI: [国内服务器伪装网站]"
echo "=============================================="

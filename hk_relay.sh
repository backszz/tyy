#!/bin/bash
# 香港CN2 GIA中转服务器部署脚本
# 保存到: https://raw.githubusercontent.com/backszz/tyy/main/hk_relay.sh

# 配置参数
CHINA_PORT="443"             # 国内服务器端口（固定）
LOCAL_PORT="443"             # 香港监听端口（固定443）
RELAY_PORT="10086"           # 本地管理端口

# 用户输入国内服务器信息
read -p "请输入天翼云服务器IP: " CHINA_IP
read -p "请输入UUID: " UUID
read -p "请输入Public Key: " PUBLIC_KEY
read -p "请输入Short ID: " SHORT_ID
read -p "请输入伪装目标网站: " TARGET_DOMAIN

# 安装必要组件
echo "正在安装必要组件..."
apt update
apt install -y iptables-persistent netfilter-persistent qrencode jq

# 启用IP转发
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# 配置端口转发
echo "配置端口转发规则..."
iptables -t nat -A PREROUTING -p tcp --dport $LOCAL_PORT -j DNAT --to-destination $CHINA_IP:$CHINA_PORT
iptables -t nat -A POSTROUTING -d $CHINA_IP -p tcp --dport $CHINA_PORT -j MASQUERADE

# 保存防火墙规则
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1

# 开放中转端口
ufw allow $LOCAL_PORT/tcp
ufw reload >/dev/null 2>&1

# 生成客户端配置
echo "生成客户端配置..."
CLIENT_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "CN_GIA_Relay",
  "add": "$(curl -4s ifconfig.co)",
  "port": "$LOCAL_PORT",
  "id": "$UUID",
  "aid": "0",
  "scy": "none",
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
  "spx": "/",
  "flow": "xtls-rprx-vision"
}
EOF
)

# 生成V2rayN兼容链接
VLESS_LINK="vless://$UUID@$(curl -4s ifconfig.co):$LOCAL_PORT?security=reality&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&sni=$TARGET_DOMAIN&type=tcp&flow=xtls-rprx-vision#香港CN2中转"

# 生成二维码
echo "$VLESS_LINK" | qrencode -o /root/client_config.png -t png
echo "$VLESS_LINK" | qrencode -t UTF8

# 创建简易管理面板
echo "创建管理面板..."
cat > /usr/local/bin/relay_manager <<EOF
#!/bin/bash
while true; do
  clear
  echo "======================================="
  echo "  香港CN2 GIA中转服务器管理面板"
  echo "======================================="
  echo "  1. 查看当前连接数"
  echo "  2. 查看实时流量"
  echo "  3. 显示客户端二维码"
  echo "  4. 显示客户端配置链接"
  echo "  5. 重启中转服务"
  echo "  0. 退出"
  echo "======================================="
  read -p "请输入选项: " choice
  
  case \$choice in
    1)
      echo "当前连接数: \$(netstat -an | grep ESTAB | grep $LOCAL_PORT | wc -l)"
      ;;
    2)
      if ! command -v iftop &> /dev/null; then
        apt install -y iftop
      fi
      iftop -P -n -N -t -s 10 -L 100 -f "dst host $CHINA_IP"
      ;;
    3)
      echo ""
      qrencode -t UTF8 < <(echo "$VLESS_LINK")
      echo ""
      echo "二维码图片: /root/client_config.png"
      ;;
    4)
      echo ""
      echo "VLESS链接:"
      echo "$VLESS_LINK"
      echo ""
      ;;
    5)
      netfilter-persistent reload
      echo "中转服务已重启"
      ;;
    0)
      exit 0
      ;;
    *)
      echo "无效选项"
      ;;
  esac
  
  read -p "按Enter键继续..."
done
EOF

chmod +x /usr/local/bin/relay_manager

# 输出部署信息
clear
echo "=================================================="
echo "  香港CN2 GIA中转服务器部署成功！"
echo "=================================================="
echo "  服务器IP: $(curl -4s ifconfig.co)"
echo "  监听端口: $LOCAL_PORT (固定)"
echo "  目标服务器: $CHINA_IP:$CHINA_PORT"
echo "  管理命令: relay_manager"
echo "=================================================="
echo "  客户端二维码:"
echo ""
qrencode -t UTF8 < <(echo "$VLESS_LINK")
echo ""
echo "  客户端配置链接:"
echo "  $VLESS_LINK"
echo "=================================================="
echo "  泰国用户请使用此二维码或链接配置客户端"
echo "=================================================="

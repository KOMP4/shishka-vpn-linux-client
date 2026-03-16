#!/bin/bash

# --- НАСТРОЙКИ ---
INTERFACE="wlp0s20f3"
VPN_SERVER="103.228.168.11"
VPN_PORT="45173"
TUN_ADDR="198.18.0.1"
LIST_FILE="/etc/shadowsocks-libdev/vpn.list"

# РЕЖИМ РАБОТЫ: "selective" (только список) или "full" (весь трафик)
MODE="full"

case "$1" in
  pre-start)
    kill $(cat /tmp/ss-local.pid 2>/dev/null) 2>/dev/null || true
    rm -f /tmp/ss-local.pid
    ip link delete tun0 2>/dev/null || true
    iptables -t mangle -F OUTPUT 2>/dev/null || true
    sleep 1
    ip tuntap add mode tun dev tun0
    ip addr add $TUN_ADDR/15 dev tun0
    ip link set dev tun0 up
    ;;

  up)
    GW=$(ip route show default | grep $INTERFACE | awk '/default/ {print $3}' | head -n 1)
    ip route add $VPN_SERVER/32 via $GW dev $INTERFACE 2>/dev/null || true
    
    # Оптимизация TCP (настройки из прошлого шага)
    iptables -t mangle -A OUTPUT -d $VPN_SERVER -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 500
    iptables -t mangle -A OUTPUT -d $VPN_SERVER -p tcp --dport $VPN_PORT -j TCPMSS --set-mss 1300
    ip link set dev tun0 mtu 1380

    if [ "$MODE" == "full" ]; then
        echo "Режим: ПОЛНЫЙ ТУННЕЛЬ. Весь трафик идет через VPN."
        ip route add default via $TUN_ADDR dev tun0 metric 1
    else
        echo "Режим: ВЫБОРОЧНЫЙ. Через VPN идут только адреса из списка."
        if [ -f "$LIST_FILE" ]; then
            while read -r line || [ -n "$line" ]; do
                [[ -z "$line" || "$line" =~ ^# ]] && continue
                ip route add "$line" via "$TUN_ADDR" dev tun0 2>/dev/null
            done < "$LIST_FILE"
        fi
    fi

    # DNS через TCP (чтобы не было утечек в селективном режиме)
    echo -e "nameserver 8.8.8.8\noptions use-vc" > /etc/resolv.conf
    ;;

  down)
    # Удаляем все маршруты через tun0 (универсальный сброс)
    ip route flush dev tun0 2>/dev/null
    ip route del $VPN_SERVER/32 2>/dev/null || true
    iptables -t mangle -F OUTPUT 2>/dev/null || true
    ip link delete tun0 2>/dev/null || true
    kill $(cat /tmp/ss-local.pid 2>/dev/null) 2>/dev/null || true
    rm -f /tmp/ss-local.pid
    systemctl restart NetworkManager
    echo "VPN выключен."
    ;;
esac

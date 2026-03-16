#!/bin/bash

# --- НАСТРОЙКИ ---
INTERFACE="ВАШ_ИНТЕРФЕЙС"
VPN_SERVER="АДРЕСС_СЕРВЕРА_ИЗ_КЛЮЧА"
VPN_PORT=ПОРТ_ИЗ_КЛЮЧА

# Удаляем старые правила, чтобы не было конфликтов и дублей
iptables -F
iptables -t nat -F
iptables -t mangle -F
# Удаляем старый маршрут к серверу, чтобы прописать его заново без ошибок
ip route del $VPN_SERVER/32 2>/dev/null || true

# Определяем текущий шлюз роутера
GW=$(ip route show default | grep $INTERFACE | awk '/default/ {print $3}' | head -n 1)
if [ -n "$GW" ]; then
    # Принудительно направляем трафик до сервера VPN через Wi-Fi
    ip route add $VPN_SERVER/32 via $GW dev $INTERFACE
    echo "Маршрут до сервера $VPN_SERVER проложен через $INTERFACE (GW: $GW)"
fi

# ФИКС DPI И ОБХОД БЕЛЫХ СПИСКОВ
# Сначала чистим старые правила mangle, чтобы не плодить дубли
iptables -t mangle -F POSTROUTING 2>/dev/null || true
iptables -t mangle -F OUTPUT 2>/dev/null || true

# АВТО-MSS: Подстраиваем размер пакета под текущую сеть (МТС или провод)
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Фрагментация первого пакета данных. 
# Это заставляет систему дробить начало сессии Shadowsocks, 
# что сбивает с толку DPI, ожидающий четкую сигнатуру протокола.
# Устанавливаем крошечный MSS только для первого пакета к серверу VPN
iptables -t mangle -A OUTPUT -d $VPN_SERVER -p tcp --dport $VPN_PORT --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 500

echo "Фиксы DPI применены. Подготовка завершена."
# Как настроить VPN клиент на базе Shadowsocks self-hosted outline server в linux

## Установка софта
Используется связка из shadowsocks-libev как прокси и tun2socks как тунель, т.к. встроенная прокси tun2socks почему-то не работает с outline серверами(

```bash
sudo apt update
sudo apt install shadowsocks-libev
```

```bash
wget https://github.com/xjasonlyu/tun2socks/releases/download/v2.6.0/tun2socks-linux-amd64.zip
unzip unzip tun2socks-linux-amd64.zip
cp tun2socks-linux-amd64 /usr/sbin/
chmod +x /usr/sbin/tun2socks-linux-amd64
```

## Настройка ss-local

создаем json
``` bash
sudo nano /etc/shadowsocks-libdev/myvpn.json
```
следующего содержания
``` json
{
    "server":"берется из конца ключа",
    "server_port":"берется из конца ключа",
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"берется из расшифровки ключа",
    "method":"chacha20-ietf-poly1305",
    "remarks": "Outline Server",
}
```

### Расшифровка ключа
Имеющийся ключ от outline имеет следующую структру
---
`ss://зашифрованый в base64 пароль@адресс сервера:порт outline/?outline=1`

---

чтобы получить пароль в нормальном, нужно, логично, декодировать его. Делается на [этом сайте](https://www.base64decode.org/)

## Создание сервиса
Для удобства и модульности выделил часть с настройкой тунеля и дроблением пакета для обхода dpi в отедльный .sh файл

```bash
sudo nano /usr/local/bin/tun-manage.sh
```

```bash
#!/bin/bash

# --- НАСТРОЙКИ ---
INTERFACE="___" # здесь нужно поставить свой интерфейс
VPN_SERVER="___" # аддрес из ключа
VPN_PORT="___" # порт из ключа
TUN_ADDR="198.18.0.1"

case "$1" in
  pre-start)
    # Полная зачистка перед стартом
    kill $(cat /tmp/ss-local.pid 2>/dev/null) 2>/dev/null || true
    rm -f /tmp/ss-local.pid
    ip link delete tun0 2>/dev/null || true
    
    # Очистка таблицы mangle (важно, чтобы правила не дублировались)
    iptables -t mangle -F OUTPUT 2>/dev/null || true
    sleep 1
    
    # Создание интерфейса
    ip tuntap add mode tun dev tun0
    ip addr add $TUN_ADDR/15 dev tun0
    ip link set dev tun0 up
    ;;

  up)
    # 1. Определяем текущий шлюз
    GW=$(ip route show default | grep $INTERFACE | awk '/default/ {print $3}' | head -n 1)
    
    # 2. Исключаем сервер VPN (маршрут напрямую через Wi-Fi)
    ip route add $VPN_SERVER/32 via $GW dev $INTERFACE 2>/dev/null || true
    
    # 3. Отключаем IPv6 (МТС часто использует его для детекции обходов)
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
    echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6

    # # 4. ТЕХНИКА TCP SPLIT (ФРАГМЕНТАЦИЯ ДАННЫХ)
    # Фрагментируем только установку соединения (SYN)
    iptables -t mangle -A OUTPUT -d $VPN_SERVER -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 500

    # Для основного трафика установите MSS побольше (например, 1300-1380)
    # Значение 40 — это и есть причина скорости 1-2 Мбит/с
    iptables -t mangle -A OUTPUT -d $VPN_SERVER -p tcp --dport $VPN_PORT -j TCPMSS --set-mss 1300

    # 5. Настройка MTU для мобильной сети
    ip link set dev tun0 mtu 1200
    
    # 6. Основной шлюз через туннель
    ip route add default via $TUN_ADDR dev tun0 metric 1
    
    # 7. DNS через TCP (форсируем использование TCP для всех запросов)
    echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1\noptions use-vc" > /etc/resolv.conf
    
    echo "VPN активирован: применена агрессивная фрагментация TCP Split (MSS 40)."
    ;;

  down)
    # Удаляем маршруты и сбрасываем правила
    ip route del $VPN_SERVER/32 2>/dev/null || true
    ip route del default via $TUN_ADDR dev tun0 2>/dev/null || true
    iptables -t mangle -F OUTPUT 2>/dev/null || true
    
    # Удаляем интерфейс и убиваем ss-local
    ip link delete tun0 2>/dev/null || true
    kill $(cat /tmp/ss-local.pid 2>/dev/null) 2>/dev/null || true
    rm -f /tmp/ss-local.pid
    
    # Возвращаем IPv6 и системный DNS
    echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
    echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6
    systemctl restart NetworkManager
    
    echo "VPN выключен, сетевые настройки сброшены."
    ;;
esac
```
---
Сам сервис:
```bash
sudo nano /etc/systemd/system/myvpn.service
```

```bash
[Unit]
Description=Combined Outline VPN
After=network.target

[Service]
Type=simple

# Вся подготовка в одном вызове
ExecStartPre=/usr/local/bin/tun-manage.sh pre-start
# Запуск ss-local
ExecStartPre=/usr/bin/ss-local -c /etc/shadowsocks-libdev/myvpn.json -u -f /tmp/ss-local.pid

# Основной процесс
ExecStart=/usr/sbin/tun2socks-linux-amd64 -device tun0 -proxy socks5://127.0.0.1:1080 -interface wlp0s20f3 # тут нужно поменять на свой

# Маршруты
ExecStartPost=/usr/local/bin/tun-manage.sh up

# Очистка
ExecStopPost=/usr/local/bin/tun-manage.sh down

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Как узнать имя своего интерфейса
для ввода в bash скрипт и сам .service
```
nmcli dev
```
Обычно интерфейсы Ethernet начинаются с `e` (например `enp2s0`), Wi-Fi — с `w` `(wlan0)`, одно из этого вам и нужно

---
## Использование
После перезагрузки можно просто делать

`sudo systemctl start myvpn.service`

и

`sudo systemctl stop myvpn.service`

иногда забиватеся буфер ss-local так что нужно иногда перезагружать его, понять это можно в `systemctl status`


# Как настроить VPN клиент на базе Shadowsocks self-hosted outline server в linux

## Установка софта

В отличеие от `legacy_version` используется решение [sing-box](https://sing-box.sagernet.org/) включающее в себя все необходимое.

### Установка

#### Debian / APT
```bash
sudo mkdir -p /etc/apt/keyrings &&
   sudo curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc &&
   sudo chmod a+r /etc/apt/keyrings/sagernet.asc &&
   echo '
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
' | sudo tee /etc/apt/sources.list.d/sagernet.sources &&
   sudo apt-get update &&
   sudo apt-get install sing-box # or sing-box-beta
```
P.S. Это все одна команда
```bash
sudo apt-get install sing-box
```


## Настройка sing-box
По мере обновлений тут будут появлятся разделы и с другими протоколами


## ShadowSocks


### Расшифровка ключа
#### Имеющийся ключ от outline имеет следующую структру

`ss://зашифрованый в base64 пароль@адресс сервера:порт outline/?outline=1`


чтобы получить пароль в нормальном виде, нужно декодировать его. Делается на [этом сайте](https://www.base64decode.org/)

---

### Как узнать имя своего интерфейса
для ввода в bash скрипт и сам .service
```
nmcli dev
```
Обычно интерфейсы Ethernet начинаются с `e` (например `enp2s0`), Wi-Fi — с `w` `(wlan0)`, одно из этого вам и нужно

---


### Скопируйте скрипт `tun-manage.sh` в `/usr/local/bin/`

```bash
sudo wget https://raw.githubusercontent.com/KOMP4/shishka-vpn-linux-client/refs/heads/main/sing-manage.sh -P /usr/local/bin/
```
### Отредактируйте раздел настройки в скрипте

```
sudo nano /usr/local/bin/sing-manage.sh
```
```bash
# --- НАСТРОЙКИ ---
INTERFACE="ваш интерфейс"
VPN_SERVER="адресс сервера из ключа"
```
### Скопируйте конфиг в `/etc/sing-box/`
```bash
sudo wget https://raw.githubusercontent.com/KOMP4/shishka-vpn-linux-client/refs/heads/main/config.json -P /etc/sing-box/
```
### Настройте конфиг

```
sudo nano /etc/sing-box/config.json
```

Отредайктируйте раздел `outbounds` вставив в нужные поля IP вашего сервера, порт и пароль

```json
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "proxy",
      "server": "IP_ВАШЕГО_СЕРВЕРА",
      "server_port": ПОРТ_ВАШЕГО_СЕРВЕРА,
      "method": "chacha20-ietf-poly1305",
      "password": "ДЕКОДИРОВАННЫЙ ПАРОЛЬ",
      "tcp_multi_path": true,
      "tcp_fast_open": true,
      //"prefix": "\u0016\u0003\u0001\u0000\u00a8\u0001\u0001",
      "udp_over_tcp": {
        "enabled": true,
        "version": 2
      },
    "multiplex": {
      "enabled": true,
      "protocol": "smux",
      "max_streams": 32,
      "padding": true
      }
    },
    {
      "type": "direct",
      "tag": "direct",
      "bind_interface": "ВАШ ИНТЕРФЕЙС"
    }
  ],
```
В следующем разделе `route`
```json
"route": {
  "rules": [
    {
      "ip_cidr": ["IP_ВАШЕГО_СЕРВЕРА/32"], 
      "outbound": "direct"
    },
```
Проверить конфиг можно командой
```
sudo env ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c /etc/sing-box/config.json
```
`WARN` сообщения игнорируйте, если нет `ERROR` или `FATAL` значит все правильно

### Отредактируйте сервис
``` 
sudo systemctl edit sing-box
```

вставьте в `[Service]`
```
[Service]
Environment="ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true"
Environment="ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM=true"
Environment="ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true"
ExecStartPre=/usr/local/bin/sing-manage.sh
LimitNOFILE=65535
```
## Использование
После `sudo systemctl daemon-reload` можно делать

`sudo systemctl start myvpn.service`
и
`sudo systemctl stop myvpn.service`
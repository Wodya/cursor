# Почему VPN через HAProxy молчит на одной Ubuntu 24

Симптом: несколько VPN заведены через HAProxy. На Windows 11 — ок. У коллеги рядом, та же сеть, Ubuntu 24 — ок. На вашей Ubuntu — ни один туннель.

Это почти никогда не «Ubuntu 24 не умеет VPN». Коллега на той же ОС и сети это уже доказал. Ломается слой **на этой машине**, общий для всех профилей: сам HAProxy, `localhost`/IPv6, firewall/kill-switch, DNS или TUN.

## 1. Сначала снять снимок

```bash
sudo bash scripts/diagnose-vpn-haproxy.sh | tee /tmp/vpn-haproxy-diag.txt
```

Дальше правьте по первому совпавшему пункту. Не применяйте все сразу.

## 2. HAProxy на Ubuntu реально не запущен

Самая частая причина, если конфиг переносили с Windows.

Проверка:

```bash
systemctl status haproxy --no-pager -l
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
ss -lntup | grep haproxy
```

Типичные поломки конфига с Windows:

| Что в `haproxy.cfg` | Что сделать |
| --- | --- |
| CRLF (`^M` в конце строк) | `sudo sed -i 's/\r$//' /etc/haproxy/haproxy.cfg` |
| Пути `C:\...`, `Program Files` | заменить на Linux-пути, certs положить в `/etc/haproxy/certs/` |
| `user` / `group`, которых нет | `getent passwd haproxy` или убрать `user`/`group` для проверки |
| `bind :443` без root / capabilities | запускать unit `haproxy.service` от root, не вручную из-под user |

Пакет:

```bash
sudo apt update
sudo apt install --reinstall haproxy
sudo systemctl enable --now haproxy
```

Если `haproxy -c` красный — ни один VPN через него не взлетит, пока конфиг не станет валидным Linux-конфигом.

## 3. `localhost` на Ubuntu — это `::1`, на Windows часто `127.0.0.1`

Если HAProxy слушает только IPv4:

```
bind 127.0.0.1:1194
bind 127.0.0.1:1080
```

а клиенты (OpenVPN, Xray, Outline, и т.д.) написаны как:

```
remote localhost 1194
```

то Ubuntu 24 резолвит `localhost` в `::1` **первым**. Соединение идёт в IPv6-loopback, где HAProxy не слушает. Все профили падают одинаково. Windows при этом может ходить в `127.0.0.1`. Коллега мог прописать `127.0.0.1` или bind на `*` / `[::1]`.

Проверка:

```bash
getent ahosts localhost
ss -lntup | grep -E '127.0.0.1|\[::1\]|\*'
```

Исправление (достаточно одного):

- В клиентах заменить `localhost` на `127.0.0.1`.
- Или в HAProxy слушать оба стека:

```
bind 127.0.0.1:1194
bind [::1]:1194
```

## 4. Хвосты от старого VPN: nftables / iptables / `ip rule`

Если раньше стояли WARP, Amnezia, Proton, Nord, Outline, Clash, sing-box — kill-switch мог остаться после удаления GUI. Тогда **любой** новый VPN умирает, хотя сеть «как у коллеги».

Проверка:

```bash
sudo nft list ruleset
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v
ip rule
ip route
```

Ищите чужие цепочки и policy rules (не только `local/main/default`).

Осторожный сброс, если уверены, что нет других нужных правил:

```bash
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
sudo nft flush ruleset
```

UFW, если включён и режет исходящие:

```bash
sudo ufw status verbose
# временно:
sudo ufw disable
```

Потом сразу проверьте один VPN. Если ожил — верните firewall точечно, не оставляйте дырявым.

## 5. Нет `/dev/net/tun`

Без TUN OpenVPN и многие userspace-клиенты не поднимают интерфейс.

```bash
ls -l /dev/net/tun
sudo modprobe tun
```

## 6. DNS живёт в `systemd-resolved`, не в `/etc/resolv.conf`

Туннель может подняться, а «интернет не работает», потому что Ubuntu 24 не применяет DNS, который пушит VPN. Windows это делает иначе, коллега мог поставить `openvpn-systemd-resolved` или NetworkManager.

```bash
resolvectl status
ls -l /etc/resolv.conf
```

Для OpenVPN:

```bash
sudo apt install openvpn-systemd-resolved
```

В `.ovpn`:

```
script-security 2
up /etc/openvpn/update-systemd-resolved
down /etc/openvpn/update-systemd-resolved
down-pre
```

Проверка после коннекта: `resolvectl status` показывает DNS на `tun0`/`wg0`.

## 7. OpenSSL 3 / TLS (реже, потому что у коллеги тоже 24.04)

Имеет смысл, только если handshake падает в логе (`certificate verify failed`, `ca md too weak`, `handshake failure`), а коллега использует **другой клиент** или ослабленный `openssl.cnf`.

Для старого OpenVPN-сервера, который вы не можете обновить, в `.ovpn` иногда помогает:

```
tls-cipher DEFAULT:@SECLEVEL=0
```

Не ставьте это «на всякий случай», если в логах нет TLS-ошибки.

## 8. Что прислать, если после скрипта всё ещё мёртво

1. Полный вывод `diagnose-vpn-haproxy.sh`.
2. Кусок `haproxy.cfg`: `frontend`/`listen`/`bind`/`server` **без** паролей и ключей.
3. Как именно подключаетесь на Ubuntu (OpenVPN CLI, NetworkManager, Xray/Nekoray, Outline, Amnezia, WireGuard).
4. Одна строка ошибки клиента и `journalctl -u haproxy -n 80 --no-pager`.
5. Меняли ли `localhost` на `127.0.0.1`.

По этим пяти вещам обычно видно, какой из пунктов 2–6 сработал.

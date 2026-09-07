# Browsec на Ubuntu: расширение живое, десктоп пишет «Connection is blocked»

Скриншоты: Premium до 2027, пинги стран есть (Norway 30 ms, Poland 56 ms), режим **Full Protection**, туннель не поднимается. Сообщение:

> Connection is blocked. We're working on it. Try again or change country — it'll be back soon!

Это не «сервер Польши лёг». API Browsec отвечает (иначе не было бы пингов и логина). Ломается **системный туннель** на этой машине. Та же причина, почему не встаёт Happ: браузерный клиент и десктоп — разные протоколы.

## В чём разница

| | Расширение в Chrome/Firefox | Десктоп Browsec 1.3.2, Full Protection |
| --- | --- | --- |
| Что шифрует | Только вкладки браузера | Весь трафик ОС |
| Протокол | HTTP Proxy over TLS, порт 443 | IPsec IKEv2 (UDP **500/4500**) и/или XRay TUN |
| Нужен root / `/dev/net/tun` | Нет | Да |
| Видно файрволу как | обычный HTTPS | VPN |

Поэтому расширение работает, а «поставить на машину» — нет. Windows ставит IPsec/Wintun драйвером установщика. Ubuntu этого сама не даёт.

Официальная справка Browsec: десктоп ходит IPsec на порт 4500; второй VPN на машине не даст подключиться первому.

## Почему у коллеги та же Ubuntu 24 живая

Сеть общая, ломается **этот** компьютер:

1. **Happ (или другой VPN) ещё держит маршруты/nftables.** Full Protection + второй клиент = классический конфликт. Сначала полностью выйти из Happ, не оставлять его в трее.
2. **UFW/nftables режет UDP 500 и 4500**, а HTTPS 443 (расширение) пропускает.
3. Нет `/dev/net/tun` или модулей `xfrm` / `esp4`.
4. После `sudo happ` хвосты `tun*` / `ip rule` / nftables остаются, даже когда GUI Happ уже убит. Демон **`happd` (часто pid от root)** продолжает сам поднимать интерфейс `happ-xray`. Обычный `pkill happ` его не убивает.

Журнал с этой машины: `browbox-tun` **создаётся** (`sudo` → `/opt/Browsec/resources/xray/browbox`), DNS 172.19.0.2, затем `report handshake success: connection refused` и `Browbox connection check failed` — GUI сам сносит TUN. Проверка `ip link show browbox-tun` после ошибки будет пустой: интерфейс уже удалён. Параллельно NetworkManager пишет `device (happ-xray)` каждые ~15 с, пока жив `happd[2151]`. Касперский: `app-kaspersky-kfl@autostart` есть в user systemd.

Смена страны в приложении это не лечит: пинг есть, IKE/TUN нет.

## Касперский

Да, он часто мешает именно десктопному VPN и почти не трогает расширение.

- Расширение Browsec — HTTPS :443, веб-антивирус это пропускает или сам проксирует.
- Happ TUN и Browsec Full Protection — IPsec UDP 500/4500, ESP, `/dev/net/tun`. Сетевой экран Касперского это часто считает атакой или «шифрованным каналом» и режет. Сообщение Browsec «Connection is blocked» на это похоже.
- На Windows исключения для VPN обычно уже стоят; у коллеги на Ubuntu Касперского может не быть.

Проверка, есть ли он на этой Ubuntu:

```bash
dpkg -l | grep -iE 'kasp|kesl'
systemctl is-active kesl 2>/dev/null
lsmod | grep -iE 'kasp|klue|kesl'
```

Тест на 5 минут: в Каспере **Pause protection** / остановить `kesl`, затем снова подключить **только** Browsec (без sudo, без Happ). Если туннель встаёт — верните защиту и добавьте в исключения:

- `/opt/Browsec/browsec-desktop` и `/opt/happ/bin/Happ`
- UDP 500 и 4500
- отключите сканирование шифрованного трафика / Network Threat Protection для этих приложений

Не оставляйте защиту выключенной. Если пауза ничего не меняет — Касперский ни при чём, смотрите leftover от Happ.

## Что сделать сейчас

В этом порядке, не всё сразу.

**1. Выключить Happ целиком, не только GUI**

```bash
systemctl status happd --no-pager
ps aux | grep -iE 'happd|happ-xray|browbox'
sudo systemctl stop happd
sudo systemctl disable happd
sudo pkill -9 happd
sudo pkill -9 -f happ-xray
sudo ip link delete happ-xray 2>/dev/null
ip -br link
ip rule
```

Пока в `ps` есть `happd` или в `ip link` есть `happ-xray`, Browsec Full Protection будет падать с `Browbox connection check failed`.

Чтобы демон не поднялся снова:

```bash
sudo systemctl mask happd
```

Если `happd` уже `inactive`, а Browsec всё равно blocked — дальше Касперский `kfl` и хвосты маршрутов/Docker:

```bash
ip rule
ip route
systemctl is-active kfl
systemctl status kfl --no-pager
sudo systemctl stop kfl
sudo iptables -L -n | head -n 40
```

Потом снова только Browsec из меню. Пришлите `ip rule` и 30 секунд journalctl вокруг новой попытки.

**2. Проверить IPsec и TUN:**

```bash
ls -l /dev/net/tun
sudo modprobe tun
lsmod | grep -E 'xfrm|esp4|af_key'
sudo ufw status verbose
```

Если UFW active:

```bash
sudo ufw allow 500/udp
sudo ufw allow 4500/udp
```

**3. Browsec — Electron, `sudo` запрещён.**

```
Running as root without --no-sandbox is not supported.
```

`%U` — плейсхолдер из `.desktop`, в терминал его не копируют. Запуск своим пользователем:

```bash
/opt/Browsec/browsec-desktop --ozone-platform=x11
```

Или ярлык в меню приложений. Full Protection → страна → тумблер. Если leftover от Happ — сначала reboot, потом только Browsec.

**4. Логи.** В левом меню **Logs directory**. Ищите `permission`, `tun`, `IKE`, `4500`, `xfrm`, `blocked`, `netlink`. Без ключей можно прислать последние 80 строк.

**5. Снимок машины:**

```bash
sudo bash scripts/diagnose-vpn-happ.sh | tee /tmp/happ-diag.txt
```

Скрипт снимает и Happ, и Browsec (пакет, UDP 500/4500, xfrm).

Пока десктоп мёртв, для браузера оставляйте расширение — оно на эту поломку не опирается.

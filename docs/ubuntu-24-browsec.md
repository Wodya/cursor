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
4. Ярлык запускает GUI без прав на туннель (как `happ` без sudo).

Смена страны в приложении это не лечит: пинг есть, IKE/TUN нет.

## Что сделать сейчас

В этом порядке, не всё сразу.

**1. Убить другие VPN** (Happ, WARP, Amnezia, Outline, Proton):

```bash
pkill -i happ; pkill -i xray; pkill -i tun2proxy
ip rule
ip -br link
```

Лишние `ip rule` и интерфейсы `tun0`/`xray0` после закрытия Happ — хвост kill-switch.

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

**3. Запустить десктоп с правами и только его:**

```bash
sudo /opt/Browsec/browsec   # путь может быть /opt/browsec или browsec в PATH
# либо из каталога приложения, который открывает пункт «Logs directory»
```

В приложении снова Full Protection → другая страна (не только Poland) → тумблер.

**4. Логи.** В левом меню **Logs directory**. Ищите `permission`, `tun`, `IKE`, `4500`, `xfrm`, `blocked`, `netlink`. Без ключей можно прислать последние 80 строк.

**5. Снимок машины:**

```bash
sudo bash scripts/diagnose-vpn-happ.sh | tee /tmp/happ-diag.txt
```

Скрипт снимает и Happ, и Browsec (пакет, UDP 500/4500, xfrm).

Пока десктоп мёртв, для браузера оставляйте расширение — оно на эту поломку не опирается.

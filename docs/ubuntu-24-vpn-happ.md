# Happ на Ubuntu 24: Windows ок, коллега ок, у вас ни один профиль

Речь про клиент **Happ** ([happ.su](https://www.happ.su/happ) / [happ.info](https://happ.info)), не HAProxy. Это GUI над Xray: VLESS/Reality, VMess, Trojan, Shadowsocks.

На Windows Happ ставит WinTun и системный прокси сам. На Ubuntu этого нет: TUN без root часто мёртв, а режим Proxy покрывает не все приложения. Если не работает **ни один** сервер — ломается клиент/режим/права на этой машине, не подписка и не сеть (коллега рядом это уже показал).

## Снимок

```bash
sudo bash scripts/diagnose-vpn-happ.sh | tee /tmp/happ-diag.txt
```

Дальше — по первому совпавшему пункту.

## 1. TUN с ярлыка не поднимается — запускайте `sudo happ`

Самая частая Linux-причина. Windows-установщик даёт драйвер и права. Linux-ярлык запускает GUI **без** `CAP_NET_ADMIN`. Ядро не создаёт `tun0`, все профили «не коннектятся».

```bash
sudo happ
```

В приложении:

1. Вручную выберите сервер слева (без выбора Happ на Linux часто не коннектится).
2. Режим: **TUN**, не только Proxy.
3. Большая кнопка питания.

Провайдеры TUN в настройках / выпадающем списке: `tun2proxy`, `Happ TUN`, `sing-box`, `xray`. Если один падает — переключите. В 4.1.1 починили Xray TUN на Linux; поставьте свежий `.deb`:

https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.deb

```bash
sudo apt install ./Happ.linux.x64.deb
```

Демон ядра (если пакет его ставит):

```bash
systemctl status happd --no-pager
sudo systemctl enable --now happd
```

Если `/opt/happ/bin/core` принадлежит `root:root`, GUI от пользователя не стартует ядра:

```bash
sudo chown -R "$USER:$USER" /opt/happ/bin/core
```

Проверка TUN:

```bash
ls -l /dev/net/tun
sudo modprobe tun
ip -br link   # после коннекта должен появиться tun0 / xray0 / utun-подобное
```

## 2. Режим Proxy на Ubuntu ≠ «весь интернет», как на Windows

Proxy вешает локальный SOCKS/HTTP. Windows подхватывает это системой. Ubuntu — только если:

- Happ включил системный прокси **и**
- GNOME: Параметры → Сеть → Прокси → вручную, **или**
- приложение само умеет SOCKS.

Snap-Firefox на Ubuntu 24 часто **игнорирует** системный прокси. Терминал, Docker, часть Electron-приложений — тоже. Тогда «ни один VPN не работает», хотя Happ зелёный.

Что делать:

- Для «как на Windows» используйте **TUN + `sudo happ`**.
- Для проверки Proxy: в Happ включите системный прокси, в Chrome/Firefox задайте SOCKS вручную на `127.0.0.1` и порт из Happ (часто 1080 / 10808), либо:

```bash
gsettings get org.gnome.system.proxy mode
curl -x socks5h://127.0.0.1:10808 https://ifconfig.me
```

Если curl через SOCKS проходит, а браузер нет — это не сервер, это прокси окружения.

## 3. Docker / nftables / старый kill-switch

TUN в режиме `system` конфликтует с Docker и хвостами WARP/Amnezia/Proton/Clash. Тогда падают все профили.

В Happ переключите стек TUN на **gvisor** (меньше зависимость от iptables).

Проверка:

```bash
sudo nft list ruleset
ip rule
sudo ufw status verbose
```

Лишние `ip rule` кроме `local/main/default` — подозрение на leftover. Не флашьте firewall вслепую.

## 4. Подписку на Linux надо выбрать и обновить отдельно

Импорт с Windows сам не переезжает. Список серверов может быть пустой, просроченный или без выбранного узла.

В Happ: отключиться → обновить подписку → **кликнуть сервер** → подключиться. Смена сервера «на лету» у Happ на Linux часто ломается: сначала disconnect.

## 5. GUI не стартует (кажется, что VPN мёртв)

Нехватка библиотек:

```bash
sudo apt install libopengl0 libgl1 libxcb1 fontconfig
```

Лог запуска:

```bash
happ 2>&1 | tee /tmp/happ-start.log
# или
sudo happ 2>&1 | tee /tmp/happ-start.log
```

## Что прислать

1. Вывод `diagnose-vpn-happ.sh`
2. Версия Happ (Help / о программе) и как запускаете: ярлык или `sudo happ`
3. Режим: Proxy / TUN / Mixed и какой TUN-провайдер
4. Есть ли `tun0` после «подключено»
5. Одна строка ошибки из Happ, без ключей и `vless://`

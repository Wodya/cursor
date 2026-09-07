# Десктопные VPN на этой Ubuntu 24

Расширение Browsec в браузере работает. Десктоп Happ и десктоп Browsec — нет. У коллеги в той же сети Ubuntu 24 живая. Значит ломается **системный туннель на этой машине**, не подписка и не Wi‑Fi.

- Браузер: HTTPS-прокси, порт 443.
- Десктоп Full Protection / Happ TUN: IPsec UDP 500/4500 и/или `/dev/net/tun`.

```bash
sudo bash scripts/diagnose-vpn-happ.sh | tee /tmp/happ-diag.txt
```

- [Happ](docs/ubuntu-24-vpn-happ.md) — `sudo happ` + TUN.
- [Browsec](docs/ubuntu-24-browsec.md) — GUI только от пользователя, не `sudo`. «Connection is blocked»: выгрузить root-Happ, снять leftover tun/nft, UDP 500/4500, логи.

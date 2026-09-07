# Диагностика Happ на Ubuntu 24

Клиент — **Happ** (Xray GUI), не HAProxy. На Windows и у коллеги на Ubuntu 24 в той же сети профили живые; на этой машине — ни один.

Агент в облаке ваш ноутбук не видит. Запустите на сломанной Ubuntu:

```bash
sudo bash scripts/diagnose-vpn-happ.sh | tee /tmp/happ-diag.txt
```

Пока вывод не пришёл, чаще всего помогает `sudo happ` + режим **TUN** и ручной выбор сервера. Разбор: [docs/ubuntu-24-vpn-happ.md](docs/ubuntu-24-vpn-happ.md).

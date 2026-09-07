# Диагностика VPN через HAProxy на Ubuntu 24

На Windows VPN через HAProxy работает, у коллеги на Ubuntu 24 в той же сети — тоже.
На этой Ubuntu не поднимается **ни один** VPN. Значит ломается **локальная машина**, а не провайдер и не сервер.

Этот репозиторий не видит ваш ноутбук: агент крутится в облаке. Запустите скрипт **на сломанной Ubuntu** и пришлите вывод.

```bash
sudo bash scripts/diagnose-vpn-haproxy.sh | tee /tmp/vpn-haproxy-diag.txt
```

Дальше — [пошаговый разбор](docs/ubuntu-24-vpn-haproxy.md).

#!/usr/bin/env bash
# Collects HAProxy + VPN client diagnostics on Ubuntu.
# Safe: read-only (except optional connectivity probes).
# Usage:
#   bash scripts/diagnose-vpn-haproxy.sh
#   sudo bash scripts/diagnose-vpn-haproxy.sh   # more complete firewall/service view

set -u
export LANG=C
export LC_ALL=C

HAVE_SUDO=0
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  HAVE_SUDO=1
elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  HAVE_SUDO=1
fi

run() {
  if [[ "${HAVE_SUDO}" -eq 1 && "${EUID:-$(id -u)}" -ne 0 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

section() {
  printf '\n========== %s ==========\n' "$1"
}

have() { command -v "$1" >/dev/null 2>&1; }

warn() { printf 'LIKELY: %s\n' "$1"; }

echo "HAProxy/VPN Ubuntu diagnostic"
echo "date:        $(date -Is 2>/dev/null || date)"
echo "user:        $(id)"
echo "sudo:        ${HAVE_SUDO}"
echo "kernel:      $(uname -a)"
echo "os:          $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"

section "1. HAProxy process / service / config"
if have haproxy; then
  echo "haproxy binary: $(command -v haproxy)"
  haproxy -v 2>&1 | head -n 5
else
  warn "haproxy binary not found in PATH (apt package haproxy not installed, or Windows-only install was copied conceptually)"
fi

if have systemctl; then
  systemctl is-enabled haproxy 2>&1 || true
  systemctl is-active haproxy 2>&1 || true
  run systemctl status haproxy --no-pager -l 2>&1 | head -n 40 || true
fi

HAPROXY_CFG=""
for candidate in \
  /etc/haproxy/haproxy.cfg \
  /usr/local/etc/haproxy/haproxy.cfg \
  "${HOME}/haproxy.cfg" \
  /opt/haproxy/haproxy.cfg; do
  if [[ -f "${candidate}" ]]; then
    HAPROXY_CFG="${candidate}"
    break
  fi
done

if [[ -z "${HAPROXY_CFG}" ]]; then
  echo "searching for haproxy.cfg..."
  HAPROXY_CFG="$(run find /etc /opt /usr/local "${HOME}" -maxdepth 4 -name 'haproxy.cfg' 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "${HAPROXY_CFG}" ]]; then
  echo "config: ${HAPROXY_CFG}"
  ls -l "${HAPROXY_CFG}" 2>/dev/null || run ls -l "${HAPROXY_CFG}"
  if grep -q $'\r' "${HAPROXY_CFG}" 2>/dev/null; then
    warn "haproxy.cfg has CRLF (Windows) line endings — HAProxy on Linux often fails to parse this"
  fi
  if grep -Eiq 'C:\\\\|/cygdrive/|Program Files|\\\\haproxy' "${HAPROXY_CFG}" 2>/dev/null; then
    warn "haproxy.cfg contains Windows paths — will not work on Ubuntu"
  fi
  if grep -Eiq 'bind[[:space:]]+127\.0\.0\.1' "${HAPROXY_CFG}" 2>/dev/null \
     && ! grep -Eiq 'bind[[:space:]]+(\[::1\]|:::|ipv6@)' "${HAPROXY_CFG}" 2>/dev/null; then
    warn "HAProxy binds IPv4 127.0.0.1 only. If VPN clients use remote localhost, Ubuntu will try ::1 first and the connection will fail. Use 127.0.0.1 in clients or also bind :::port / [::1]:port"
  fi
  echo "----- bind / frontend / backend (redacted) -----"
  grep -Eiv 'password|passphrase|secret|keyfile' "${HAPROXY_CFG}" \
    | grep -Ei '^(global|defaults|frontend|backend|listen)|bind |server |mode |timeout |ssl ' \
    | head -n 200
  if have haproxy; then
    echo "----- haproxy -c -----"
    run haproxy -c -f "${HAPROXY_CFG}" 2>&1 || warn "HAProxy config check failed — service will not start"
  fi
else
  warn "no haproxy.cfg found — HAProxy is not installed/configured on this Ubuntu"
fi

section "2. Listening sockets (vpn / proxy typical ports)"
if have ss; then
  run ss -lntup 2>/dev/null | grep -Ei 'haproxy|openvpn|wg|xray|v2ray|sing-box|outline|tun2socks|stunnel|nginx|:443 |:1194 |:51820 |:1080 |:8080 |:8443 |:9443 |:10443 ' || run ss -lntup | head -n 80
elif have netstat; then
  run netstat -lntup | head -n 80
fi

section "3. TUN/TAP and VPN interfaces"
if [[ -e /dev/net/tun ]]; then
  ls -l /dev/net/tun
else
  warn "/dev/net/tun is missing — OpenVPN/WireGuard-userspace cannot work. Try: sudo modprobe tun && sudo mkdir -p /dev/net && sudo mknod /dev/net/tun c 10 200"
fi
lsmod 2>/dev/null | grep -Ei 'tun|tap|wireguard' || echo "lsmod: tun/wireguard not listed (may still be built-in)"
echo "interfaces:"
if have ip; then
  ip -br link
  ip -br addr
else
  ls /sys/class/net
  ifconfig -a 2>/dev/null || true
fi

section "4. Routes and policy routing"
if have ip; then
  echo "----- ip route -----"
  ip route
  echo "----- ip -6 route -----"
  ip -6 route 2>/dev/null | head -n 40
  echo "----- ip rule -----"
  ip rule
  echo "----- ip -6 rule -----"
  ip -6 rule 2>/dev/null || true
  if ip rule | grep -qv 'from all lookup \(local\|main\|default\)'; then
    echo "(extra policy rules present — leftover VPN kill-switch / WARP / Amnezia is a common cause)"
  fi
else
  route -n 2>/dev/null || true
fi

section "5. DNS / systemd-resolved"
echo "----- /etc/resolv.conf -----"
ls -l /etc/resolv.conf 2>/dev/null || true
cat /etc/resolv.conf 2>/dev/null || true
if have resolvectl; then
  echo "----- resolvectl status -----"
  resolvectl status 2>&1 | head -n 80
fi
if have systemctl; then
  systemctl is-active systemd-resolved 2>&1 || true
fi
getent hosts localhost 2>/dev/null || true
echo "localhost resolution:"
getent ahosts localhost 2>/dev/null || true
if getent ahosts localhost 2>/dev/null | grep -q '::1'; then
  echo "NOTE: localhost has AAAA ::1 — VPN 'remote localhost' will hit IPv6 first"
fi

section "6. Firewall / leftover kill-switch"
if have ufw; then
  echo "----- ufw -----"
  run ufw status verbose 2>&1 || true
fi
if have nft; then
  echo "----- nft ruleset (first 200 lines) -----"
  run nft list ruleset 2>&1 | head -n 200
  if run nft list ruleset 2>/dev/null | grep -Eiq 'warp|amnezia|proton|mullvad|nord|outline|clash|sing-box|kill.?switch|drop'; then
    warn "nftables contains VPN/kill-switch-like rules. Leftover firewall is a top reason ALL VPNs fail on one Ubuntu box"
  fi
fi
if have iptables; then
  echo "----- iptables -----"
  run iptables -L -n -v 2>&1 | head -n 80
  echo "----- iptables nat -----"
  run iptables -t nat -L -n -v 2>&1 | head -n 40
fi
if have iptables-save; then
  if run iptables-save 2>/dev/null | grep -Eiq 'warp|amnezia|proton|mullvad|nord|cf-warp|wg-quick'; then
    warn "iptables-save mentions a VPN product — leftover rules can blackhole traffic"
  fi
fi

section "7. Leftover VPN / proxy software"
echo "installed-ish binaries:"
for bin in \
  openvpn wg wg-quick wireguard nm-openvpn \
  xray v2ray sing-box clash clash-meta mihomo \
  outline-client outline \
  warp-cli cloudflared \
  protonvpn protonvpn-cli nordvpn mullvad \
  amnezia amneziawg amnezia-vpn \
  stunnel stunnel4 gost \
  tun2socks hiddify nekoray; do
  if have "${bin}"; then
    echo "  FOUND ${bin}: $(command -v "${bin}")"
  fi
done
echo "systemd units matching vpn/proxy:"
if have systemctl; then
  systemctl list-units --all --no-pager --type=service 2>/dev/null \
    | grep -Ei 'haproxy|openvpn|wireguard|wg-quick|xray|v2ray|sing-box|clash|warp|amnezia|outline|stunnel|nord|proton|mullvad' \
    || echo "  (none)"
fi
echo "NetworkManager VPN connections:"
if have nmcli; then
  nmcli -t -f NAME,TYPE,DEVICE,STATE connection show 2>/dev/null | grep -i vpn || echo "  (none)"
fi

section "8. Environment proxy / IPv6 / rp_filter / time"
echo "proxy env:"
env | grep -Ei '^(http|https|all|no)_proxy=' || echo "  (none)"
echo "IPv6 sysctl:"
sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv6.bindv6only 2>/dev/null || true
echo "rp_filter:"
sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter 2>/dev/null || true
echo "ip_forward:"
sysctl net.ipv4.ip_forward 2>/dev/null || true
echo "time:"
date -Is 2>/dev/null || date
timedatectl 2>/dev/null | head -n 20 || true
if have timedatectl && timedatectl 2>/dev/null | grep -qi 'NTP service: inactive'; then
  warn "NTP inactive — TLS VPN handshakes fail if clock is wrong"
fi

section "9. AppArmor / OpenSSL"
if have aa-status; then
  run aa-status 2>/dev/null | grep -Ei 'haproxy|openvpn|xray' || echo "  (no matching apparmor profiles loaded)"
elif [[ -d /etc/apparmor.d ]]; then
  ls /etc/apparmor.d | grep -Ei 'haproxy|openvpn' || true
fi
if have openssl; then
  openssl version
  echo "OpenSSL SECLEVEL from openssl.cnf:"
  grep -Rsn 'SECLEVEL\|CipherString' /etc/ssl/openssl.cnf 2>/dev/null | head -n 20 || true
fi

section "10. Connectivity probes"
echo "Default v4 route ping:"
ping -4 -c 2 -W 2 1.1.1.1 2>&1 | tail -n 5 || warn "cannot ping 1.1.1.1 — local routing/firewall/kill-switch"
echo "DNS probe:"
if have getent; then
  getent ahosts example.com | head -n 5 || warn "DNS resolution failed"
fi
if [[ -n "${HAPROXY_CFG}" ]]; then
  echo "Probing HAProxy server lines (TCP):"
  grep -E '^[[:space:]]*server[[:space:]]' "${HAPROXY_CFG}" 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9a-zA-Z._-]+:[0-9]+$/) print $i}' \
    | sort -u \
    | head -n 20 \
    | while read -r endpoint; do
        host="${endpoint%:*}"; port="${endpoint##*:}"
        echo -n "  ${host}:${port} ... "
        if have timeout; then
          if timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
            echo "TCP open"
          else
            echo "TCP FAIL"
          fi
        elif have nc; then
          nc -zv -w 3 "${host}" "${port}" 2>&1 | tail -n 1
        else
          echo "no timeout/nc"
        fi
      done
fi

section "11. Recent logs"
if have journalctl; then
  echo "----- haproxy journal (last 80) -----"
  run journalctl -u haproxy -n 80 --no-pager 2>&1 || true
  echo "----- kernel tun / apparmor (last) -----"
  run journalctl -k -n 50 --no-pager 2>&1 | grep -Ei 'tun|haproxy|apparmor|ufw|denied' || true
fi
echo "----- syslog grep -----"
run grep -Ei 'haproxy|openvpn|wireguard' /var/log/syslog /var/log/haproxy.log 2>/dev/null | tail -n 40 || true

section "DONE"
echo "Re-run with sudo if firewall/service sections were empty."
echo "Paste this whole output when asking for the next fix."

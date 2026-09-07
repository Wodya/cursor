#!/usr/bin/env bash
# Collects Happ + Browsec desktop VPN diagnostics on Ubuntu.
# Safe: read-only except optional ping/DNS probes.
# Usage:
#   bash scripts/diagnose-vpn-happ.sh
#   sudo bash scripts/diagnose-vpn-happ.sh

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

section() { printf '\n========== %s ==========\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
warn() { printf 'LIKELY: %s\n' "$1"; }

REAL_HOME="${HOME}"
REAL_USER="${USER:-$(id -un)}"
if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  REAL_USER="${SUDO_USER}"
  REAL_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
fi

echo "Happ / Browsec desktop Ubuntu diagnostic"
echo "date:        $(date -Is 2>/dev/null || date)"
echo "user:        $(id)"
echo "real user:   ${REAL_USER} home=${REAL_HOME}"
echo "sudo:        ${HAVE_SUDO}"
echo "kernel:      $(uname -a)"
echo "os:          $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
echo "session:     XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-?} DISPLAY=${DISPLAY:-?} WAYLAND=${WAYLAND_DISPLAY:-?}"

section "1. Happ package / binary / version"
if have dpkg; then
  dpkg -l 'happ*' 'Happ*' 2>/dev/null | grep -E '^ii' || echo "dpkg: no happ package listed"
fi
echo "binaries in PATH:"
for bin in happ Happ happd; do
  if have "${bin}"; then
    echo "  ${bin}: $(command -v "${bin}") -> $(readlink -f "$(command -v "${bin}")" 2>/dev/null || true)"
  fi
done
echo "install trees:"
for d in /opt/happ /opt/Happ /usr/lib/happ /usr/local/happ; do
  if [[ -d "${d}" ]]; then
    echo "  FOUND ${d}"
    ls -ld "${d}" "${d}/bin" "${d}/bin/core" 2>/dev/null || true
    ls -l "${d}/bin" 2>/dev/null | head -n 30
  fi
done
if [[ -x /opt/happ/bin/Happ ]]; then
  echo "Happ --version:"
  /opt/happ/bin/Happ --version 2>&1 | head -n 5 || true
fi
if have happ; then
  happ --version 2>&1 | head -n 5 || true
fi
echo "desktop files:"
ls -l /usr/share/applications/*[Hh]app* "${REAL_HOME}/.local/share/applications/"*[Hh]app* 2>/dev/null || echo "  (none)"
grep -H '^Exec=' /usr/share/applications/*[Hh]app*.desktop "${REAL_HOME}/.local/share/applications/"*[Hh]app*.desktop 2>/dev/null || true

section "2. Processes, happd, capabilities"
ps -eo user,pid,ppid,args | grep -Ei '[Hh]app|xray|sing-box|tun2proxy|tun2socks' | grep -v grep || echo "  Happ/xray not running"
if have systemctl; then
  for u in happd happ happ-desktop; do
    systemctl status "${u}" --no-pager -l 2>&1 | head -n 20 || true
  done
  systemctl list-units --all --no-pager --type=service 2>/dev/null \
    | grep -Ei 'happ|xray|sing-box|tun2' || echo "  (no matching systemd units)"
fi
if have getcap; then
  echo "capabilities:"
  run getcap /opt/happ/bin/* /opt/happ/bin/core/* /usr/bin/happ 2>/dev/null | head -n 40 || true
fi
if [[ -d /opt/happ/bin/core ]]; then
  owner="$(stat -c '%U:%G' /opt/happ/bin/core 2>/dev/null || true)"
  echo "core dir owner: ${owner}"
  if [[ "${owner}" == "root:root" ]]; then
    warn "/opt/happ/bin/core is root:root — GUI as user often cannot start TUN cores. Fix: sudo chown -R ${REAL_USER}:${REAL_USER} /opt/happ/bin/core"
  fi
fi

section "3. TUN device"
if [[ -e /dev/net/tun ]]; then
  ls -l /dev/net/tun
else
  warn "/dev/net/tun missing — Happ TUN cannot start. Try: sudo modprobe tun"
fi
lsmod 2>/dev/null | grep -Ei 'tun|tap|wireguard' || echo "lsmod: tun not listed (may be built-in)"
echo "tunnel-like interfaces:"
if have ip; then
  ip -br link
  ip -br addr
else
  ls /sys/class/net
fi

section "3b. Browsec desktop + IPsec (UDP 500/4500)"
if have dpkg; then
  dpkg -l '*browsec*' 2>/dev/null | grep -E '^ii' || echo "dpkg: no browsec package listed"
fi
for bin in browsec Browsec browsec-desktop; do
  if have "${bin}"; then
    echo "  ${bin}: $(command -v "${bin}")"
  fi
done
for d in /opt/Browsec /opt/browsec /usr/lib/browsec /usr/lib/Browsec; do
  [[ -d "${d}" ]] && echo "  FOUND ${d}" && ls -ld "${d}" && ls "${d}" | head -n 20
done
echo "IPsec kernel modules:"
lsmod 2>/dev/null | grep -Ei 'xfrm|esp4|esp6|ah4|af_key|xfrm_user' || echo "  (not in lsmod — may still be built-in; check: grep -i xfrm /lib/modules/$(uname -r)/modules.builtin 2>/dev/null)"
echo "UDP 500/4500 listeners:"
if have ss; then
  run ss -lunp 2>/dev/null | grep -E ':500 |:4500 ' || echo "  (nothing bound — OK if not connected yet)"
fi
echo "xfrm state/policy (IPsec SAs):"
run ip xfrm state 2>/dev/null | head -n 20 || true
run ip xfrm policy 2>/dev/null | head -n 20 || true
for d in \
  "${REAL_HOME}/.config/Browsec" \
  "${REAL_HOME}/.config/browsec" \
  "${REAL_HOME}/.config/browsec-desktop" \
  "${REAL_HOME}/.config/Browsec Desktop" \
  "${REAL_HOME}/.config/browsec-vpn" \
  "${REAL_HOME}/.local/share/Browsec" \
  "${REAL_HOME}/.local/share/browsec"; do
  if [[ -d "${d}" ]]; then
    echo "  FOUND ${d}"
    run ls -la "${d}" 2>/dev/null | head -n 30
  fi
done

section "4. Routes / leftover kill-switch"
if have ip; then
  ip route
  echo "----- ip rule -----"
  ip rule
  extra_rules="$(ip rule | grep -vE 'from all lookup (local|main|default)' || true)"
  if [[ -n "${extra_rules}" ]]; then
    echo "${extra_rules}"
    warn "extra policy routing present — leftover Happ/WARP/Amnezia kill-switch can blackhole every profile"
  fi
else
  route -n 2>/dev/null || true
fi

section "5. Firewall"
if have ufw; then
  run ufw status verbose 2>&1 || true
fi
if have nft; then
  run nft list ruleset 2>&1 | head -n 160
  if run nft list ruleset 2>/dev/null | grep -Eiq 'warp|amnezia|proton|mullvad|nord|clash|sing-box|happ|tun2proxy|drop'; then
    warn "nftables mentions VPN/proxy product or DROP — leftover rules can kill all Happ profiles"
  fi
fi
if have iptables; then
  run iptables -L -n -v 2>&1 | head -n 50
  run iptables -t nat -L -n -v 2>&1 | head -n 30
fi

section "6. System proxy (Linux Proxy mode is NOT a VPN)"
echo "env:"
env | grep -Ei '^(http|https|all|no)_proxy=' || echo "  (no *_proxy env)"
if have gsettings; then
  echo "GNOME proxy:"
  gsettings get org.gnome.system.proxy mode 2>/dev/null || true
  gsettings get org.gnome.system.proxy.socks host 2>/dev/null || true
  gsettings get org.gnome.system.proxy.socks port 2>/dev/null || true
  gsettings get org.gnome.system.proxy.http host 2>/dev/null || true
  gsettings get org.gnome.system.proxy.http port 2>/dev/null || true
  mode="$(gsettings get org.gnome.system.proxy mode 2>/dev/null || true)"
  if [[ "${mode}" == "'none'" || "${mode}" == "none" ]]; then
    warn "GNOME proxy is none. Happ Proxy mode will not cover the system; use TUN (sudo happ) or enable system proxy in Happ"
  fi
fi
if have kreadconfig5 || have kreadconfig6; then
  echo "KDE proxy hints:"
  (kreadconfig6 --file kioslaverc --group 'Proxy Settings' --key ProxyType 2>/dev/null \
    || kreadconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 2>/dev/null) || true
fi
echo "listening 1080/10808/2080/7890 (typical Happ local inbounds):"
if have ss; then
  run ss -lntup 2>/dev/null | grep -Ei '1080|10808|2080|7890|1087|10808|happ|xray|sing' || echo "  (none — core not listening; not connected or TUN-only failed)"
fi

section "7. DNS"
ls -l /etc/resolv.conf 2>/dev/null || true
cat /etc/resolv.conf 2>/dev/null || true
if have resolvectl; then
  resolvectl status 2>&1 | head -n 60
fi

section "8. Happ config / logs (secrets redacted)"
echo "config dirs:"
for d in \
  "${REAL_HOME}/.config/happ" \
  "${REAL_HOME}/.config/Happ" \
  "${REAL_HOME}/.local/share/happ" \
  "${REAL_HOME}/.local/share/Happ" \
  "${REAL_HOME}/.Happ" \
  /root/.config/happ \
  /root/.config/Happ; do
  if [[ -d "${d}" ]]; then
    echo "  FOUND ${d}"
    run ls -la "${d}" 2>/dev/null | head -n 40
  fi
done
echo "recent log files:"
run find "${REAL_HOME}/.config" "${REAL_HOME}/.local/share" /tmp /opt/happ /var/log \
  -maxdepth 4 \
  \( -iname '*happ*.log' -o -iname '*xray*.log' -o -iname '*tun2proxy*.log' \) \
  2>/dev/null | head -n 40
echo "----- last log lines -----"
run find "${REAL_HOME}/.config" "${REAL_HOME}/.local/share" /tmp /opt/happ \
  -maxdepth 4 -type f \( -iname '*happ*.log' -o -iname '*xray*.log' \) 2>/dev/null \
  | head -n 20 \
  | while read -r f; do
      case "${f}" in
        *.so*|*.png|*.jpg) continue ;;
      esac
      if file "${f}" 2>/dev/null | grep -qi 'text'; then
        echo "==> ${f}"
        run grep -Eiv 'uuid|password|privateKey|psk|token|vless://|vmess://|trojan://|ss://' "${f}" 2>/dev/null | tail -n 20
      fi
    done

section "9. Conflicting VPN software"
for bin in \
  openvpn wg warp-cli cloudflared \
  protonvpn nordvpn mullvad \
  amnezia outline clash clash-meta mihomo \
  v2ray xray sing-box hiddify nekoray; do
  if have "${bin}"; then
    echo "  FOUND ${bin}: $(command -v "${bin}")"
  fi
done

section "10. Connectivity + libraries"
echo "ping 1.1.1.1:"
ping -4 -c 2 -W 2 1.1.1.1 2>&1 | tail -n 4 || warn "no ICMP to 1.1.1.1 — routing/firewall broken even without Happ"
echo "DNS example.com:"
getent ahosts example.com 2>/dev/null | head -n 4 || warn "DNS failed"
echo "OpenGL / Qt libs Happ often needs:"
ldconfig -p 2>/dev/null | grep -E 'libOpenGL|libGL\.so|libxcb|libfontconfig' | head -n 20 || true
for lib in libOpenGL.so.0 libGL.so.1 libxcb.so.1 libfontconfig.so.1; do
  if ! ldconfig -p 2>/dev/null | grep -q "${lib}"; then
    warn "missing ${lib} — Happ GUI may fail to start (sudo apt install libopengl0 libgl1 libxcb1 fontconfig)"
  fi
done

section "11. Journal"
if have journalctl; then
  run journalctl -n 80 --no-pager -t happ -t Happ -t happd 2>&1 | tail -n 40 || true
  run journalctl -k -n 40 --no-pager 2>&1 | grep -Ei 'tun|apparmor|denied|happ' || true
fi

section "DONE"
echo "Next on this Ubuntu:"
echo "  Happ: sudo happ + TUN; pick a server; try tun2proxy if Xray TUN fails"
echo "  Browsec: NEVER sudo (Electron). Kill root Happ first; reboot if tun leftover; UDP 500/4500; Logs directory"
echo "  Browser extension can stay on — it does not use IPsec/TUN"
echo "Paste this output for the next step."

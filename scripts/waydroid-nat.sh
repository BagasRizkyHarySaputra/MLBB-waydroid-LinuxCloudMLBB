#!/usr/bin/env bash
# ============================================================
#  waydroid-nat.sh - pastikan NAT internet utk Waydroid
#  Idempotent: aman dipanggil berkali-kali.
# ============================================================
set -u
SUBNET=192.168.240.0/24

# tunggu waydroid0 muncul (maks ~20s)
for _ in $(seq 1 20); do
  ip link show waydroid0 >/dev/null 2>&1 && break
  sleep 1
done
ip link show waydroid0 >/dev/null 2>&1 || { echo "waydroid0 belum ada"; exit 0; }

sysctl -qw net.ipv4.ip_forward=1

add_rule(){ # $1=table $2=chain $3..=args
  local t=$1 c=$2; shift 2
  iptables -t "$t" -C "$c" "$@" 2>/dev/null || iptables -t "$t" -A "$c" "$@"
}
add_ins(){ # insert di depan
  local t=$1 c=$2; shift 2
  iptables -t "$t" -C "$c" "$@" 2>/dev/null || iptables -t "$t" -I "$c" 1 "$@"
}

add_rule nat POSTROUTING -s "$SUBNET" ! -d "$SUBNET" -j MASQUERADE
add_ins  filter FORWARD -i waydroid0 -j ACCEPT
add_ins  filter FORWARD -o waydroid0 -j ACCEPT
add_rule filter FORWARD -i waydroid0 -o waydroid0 -j ACCEPT

# MSS clamp (biar koneksi di dalam container stabil)
add_ins mangle FORWARD -o waydroid0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

echo "NAT waydroid OK"

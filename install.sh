#!/usr/bin/env bash
set -Eeuo pipefail

# Kali-only installer for base APT dependencies.
# ProjectDiscovery tools are NOT installed here (install via go install / official releases).

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "[x] Usa sudo ./install.sh" >&2; exit 1; }

apt update -y
apt install -y jq curl dnsutils ca-certificates whatweb wafw00f

echo "[+] Done."
echo "[+] Now install ProjectDiscovery tools if needed: subfinder/httpx/katana/nuclei/dnsx (and amass optional)."

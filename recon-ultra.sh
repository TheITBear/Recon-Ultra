#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ---------------------------
# Banner (The IT Bear edition)
# ---------------------------
banner_itbear() {
  [[ "${QUIET:-0}" == "1" ]] && return 0
  [[ -t 1 ]] || return 0

  local ORANGE="\e[38;5;202m"   # IT Bear orange
  local WHITE="\e[97m"
  local DIM="\e[2m"
  local RESET="\e[0m"

  clear

  cat <<EOF
${ORANGE}########################################################################################
#                                                                                      #
#     ʕ•ᴥ•ʔ                                                                    ʕ•ᴥ•ʔ     #
#    (  ) )        ${WHITE}██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗${ORANGE}          ( (  )    #
#   /|  |\\        ${WHITE}██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║${ORANGE}         //|  |\\   #
#    /    \\        ${WHITE}██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║${ORANGE}           //    \\  #
#   (      )       ${WHITE}██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║${ORANGE}          (      ) #
#    `-____-'      ${WHITE}██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║${ORANGE}           `-____-' #
#                     ${WHITE}╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝${ORANGE}                    #
#                                                                                      #
#                 ${WHITE}██╗   ██╗██╗  ████████╗██████╗  █████╗${ORANGE}                        #
#                 ${WHITE}██║   ██║██║  ╚══██╔══╝██╔══██╗██╔══██╗${ORANGE}                        #
#                 ${WHITE}██║   ██║██║     ██║   ██████╔╝███████║${ORANGE}                        #
#                 ${WHITE}██║   ██║██║     ██║   ██╔══██╗██╔══██║${ORANGE}                        #
#                 ${WHITE}╚██████╔╝███████╗██║   ██║  ██║██║  ██║${ORANGE}                        #
#                 ${WHITE} ╚═════╝ ╚══════╝╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝${ORANGE}                        #
#                                                                                      #
#   ${WHITE}RECON ULTRA${ORANGE} • ${WHITE}Kali-only${ORANGE} • ${WHITE}Passive | Light | Active${ORANGE}      ${DIM}by The IT Bear${RESET}${ORANGE}  #
#   ${DIM}Memento Mori • Use ONLY on assets you own or are explicitly authorized.${RESET}${ORANGE}           #
#                                                                                      #
########################################################################################${RESET}
EOF
}

# ---------------------------
# Helpers
# ---------------------------
info(){ echo "[+] $*"; }
warn(){ echo "[!] $*" >&2; }
die(){ echo "[x] $*" >&2; exit 1; }

need(){ command -v "$1" >/dev/null 2>&1; }
require(){ need "$1" || die "Dipendenza mancante: $1"; }

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

usage() {
  cat <<EOF
Usage:
  $0 -t <target> [--passive|--light|--active] [-o <outdir>] [--no-brute] [--quiet]

Options:
  -t, --target     Target domain (e.g. example.com)
  -o, --out        Output directory (default: ./out/<target>)
  --passive        Only passive OSINT (no active probing)
  --light          Low-noise enumeration (default)
  --active         Full pipeline (still rate-limited)
  --no-brute       Disable dnsx brute-force stage
  --quiet, -q      No banner
EOF
}

# ---------------------------
# Args
# ---------------------------
TARGET=""
OUTDIR=""
MODE="light"
BRUTE=1
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="${2:-}"; shift 2 ;;
    -o|--out) OUTDIR="${2:-}"; shift 2 ;;
    --passive) MODE="passive"; shift ;;
    --light) MODE="light"; shift ;;
    --active) MODE="active"; shift ;;
    --no-brute) BRUTE=0; shift ;;
    --quiet|-q) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argomento sconosciuto: $1 (usa -h)" ;;
  esac
done

[[ -n "$TARGET" ]] || { usage; exit 1; }

# ---------------------------
# Banner
# ---------------------------
banner_itbear

# ---------------------------
# Directories
# ---------------------------
OUTDIR="${OUTDIR:-./out/${TARGET}}"
SUBDIR="${OUTDIR}/subdomains"
DNSDIR="${OUTDIR}/dns"
HTTPDIR="${OUTDIR}/http"
SCANDIR="${OUTDIR}/scan"
REPORTDIR="${OUTDIR}/report"
mkdir -p "$SUBDIR" "$DNSDIR" "$HTTPDIR" "$SCANDIR" "$REPORTDIR"

# ---------------------------
# Dependencies (Kali-only policy)
# ---------------------------
require bash
require curl
require dig

# jq required for light/active (JSON parsing)
if [[ "$MODE" != "passive" ]]; then
  require jq
else
  need jq || warn "jq non presente: alcune fasi JSON potrebbero essere limitate."
fi

# Optional tools (phases will be skipped if missing)
TOOLS=(subfinder amass dnsx httpx katana nuclei whatweb wafw00f testssl.sh)
for t in "${TOOLS[@]}"; do
  need "$t" || warn "Tool mancante (fase verrà saltata): $t"
done

# ---------------------------
# Config
# ---------------------------
RATELIMIT_HTTPX="50"
RATELIMIT_KATANA="10"
RATELIMIT_NUCLEI="10"

# ---------------------------
# Phase: Subdomains (passive)
# ---------------------------
SUB_ALL="${SUBDIR}/subdomains_all.txt"
: > "$SUB_ALL"

info "Enumerazione subdomain (passive)…"

if need subfinder; then
  subfinder -d "$TARGET" -silent >> "$SUB_ALL" || true
fi

if need amass; then
  amass enum -passive -d "$TARGET" 2>/dev/null >> "$SUB_ALL" || true
fi

# crt.sh (JSON) - requires jq
if need jq; then
  info "crt.sh (Certificate Transparency)…"
  curl -fsSL "https://crt.sh/?q=%25.${TARGET}&output=json"     | jq -r '.[].name_value' 2>/dev/null     | tr '\r' '\n'     | sed 's/\*\.//g'     | awk 'NF'     | sort -u >> "$SUB_ALL" || true
else
  warn "Skip crt.sh: jq mancante"
fi

sort -u "$SUB_ALL" -o "$SUB_ALL"
info "Subdomain raccolti: $(wc -l < "$SUB_ALL" | tr -d ' ')"

# ---------------------------
# Phase: DNS brute (optional)
# ---------------------------
SUB_BRUTE="${SUBDIR}/subdomains_bruteforce.txt"
if [[ "$BRUTE" -eq 1 && "$MODE" != "passive" && -s "$SUB_ALL" ]] && need dnsx; then
  info "dnsx brute-force (noisy) abilitato…"
  WORDS="${SUBDIR}/words.txt"
  cat > "$WORDS" <<'WL'
admin
api
app
cdn
dev
files
git
mail
portal
stage
test
vpn
www
WL
  dnsx -d "$TARGET" -w "$WORDS" -silent 2>/dev/null | sort -u > "$SUB_BRUTE" || true
  cat "$SUB_BRUTE" >> "$SUB_ALL"
  sort -u "$SUB_ALL" -o "$SUB_ALL"
else
  [[ "$BRUTE" -eq 0 ]] && info "dnsx brute-force disabilitato (--no-brute)."
fi

# ---------------------------
# Phase: DNS resolve
# ---------------------------
info "Risoluzione DNS (A/AAAA/CNAME)…"
DNS_A="${DNSDIR}/A.txt"
DNS_AAAA="${DNSDIR}/AAAA.txt"
DNS_CNAME="${DNSDIR}/CNAME.txt"
: > "$DNS_A"; : > "$DNS_AAAA"; : > "$DNS_CNAME"

while read -r sub; do
  [[ -z "$sub" ]] && continue
  dig +short A "$sub" | awk 'NF{print "'"$sub"' " $0}' >> "$DNS_A" || true
  dig +short AAAA "$sub" | awk 'NF{print "'"$sub"' " $0}' >> "$DNS_AAAA" || true
  dig +short CNAME "$sub" | awk 'NF{print "'"$sub"' " $0}' >> "$DNS_CNAME" || true
done < "$SUB_ALL"

sort -u "$DNS_A" -o "$DNS_A"
sort -u "$DNS_AAAA" -o "$DNS_AAAA"
sort -u "$DNS_CNAME" -o "$DNS_CNAME"

HOSTS="${HTTPDIR}/hosts.txt"
cp "$SUB_ALL" "$HOSTS"

# ---------------------------
# Phase: HTTP probing
# ---------------------------
ALIVE="${HTTPDIR}/alive.txt"
: > "$ALIVE"

if [[ "$MODE" != "passive" && -s "$HOSTS" ]] && need httpx; then
  info "httpx probing (rate-limit ${RATELIMIT_HTTPX})…"
  httpx -l "$HOSTS" -silent -rl "$RATELIMIT_HTTPX" -title -tech-detect -status-code     | tee "$ALIVE" >/dev/null || true
else
  [[ "$MODE" == "passive" ]] && info "Mode passive: skip http probing."
  need httpx || warn "Skip httpx: non presente"
fi

# ---------------------------
# Phase: Fingerprint / WAF / TLS (optional)
# ---------------------------
if [[ "$MODE" == "active" ]]; then
  if need wafw00f && [[ -s "$ALIVE" ]]; then
    info "wafw00f…"
    awk '{print $1}' "$ALIVE" | head -n 50 | while read -r url; do
      wafw00f "$url" 2>/dev/null || true
    done > "${SCANDIR}/waf.txt"
  fi

  if need whatweb && [[ -s "$ALIVE" ]]; then
    info "whatweb…"
    awk '{print $1}' "$ALIVE" | head -n 50 | while read -r url; do
      whatweb --no-errors "$url" 2>/dev/null || true
    done > "${SCANDIR}/whatweb.txt"
  fi

  if need testssl.sh && [[ -s "$ALIVE" ]]; then
    info "testssl.sh (sample)…"
    awk '{print $1}' "$ALIVE" | grep -E '^https://' | head -n 10 | while read -r url; do
      testssl.sh --quiet "$url" 2>/dev/null || true
    done > "${SCANDIR}/tls.txt"
  fi
fi

# ---------------------------
# Phase: Crawl (optional)
# ---------------------------
CRAWL="${SCANDIR}/crawl.txt"
: > "$CRAWL"

if [[ "$MODE" != "passive" && -s "$ALIVE" ]] && need katana; then
  info "katana crawl (rate-limit ${RATELIMIT_KATANA})…"
  awk '{print $1}' "$ALIVE" | head -n 100     | katana -silent -rl "$RATELIMIT_KATANA" -d 2 2>/dev/null     | sort -u > "$CRAWL" || true
else
  need katana || warn "Skip katana: non presente"
fi

# ---------------------------
# Phase: Nuclei (optional)
# ---------------------------
NUCLEI_OUT="${SCANDIR}/nuclei.txt"
: > "$NUCLEI_OUT"

if [[ "$MODE" == "active" && -s "$ALIVE" ]] && need nuclei; then
  info "nuclei scan (rate-limit ${RATELIMIT_NUCLEI})…"
  awk '{print $1}' "$ALIVE" | nuclei -silent -rl "$RATELIMIT_NUCLEI" 2>/dev/null     | tee "$NUCLEI_OUT" >/dev/null || true
else
  [[ "$MODE" != "active" ]] && info "Mode non active: skip nuclei."
  need nuclei || warn "Skip nuclei: non presente"
fi

# ---------------------------
# Report
# ---------------------------
REPORT="${REPORTDIR}/report.html"
info "Genero report HTML…"

{
  echo "<!doctype html><html><head><meta charset='utf-8'><title>Recon-Ultra Report - ${TARGET}</title>"
  echo "<style>body{font-family:system-ui,Segoe UI,Arial;margin:24px} pre{background:#111;color:#eee;padding:12px;overflow:auto;border-radius:10px} h2{margin-top:28px}</style>"
  echo "</head><body>"
  echo "<h1>Recon-Ultra Report</h1>"
  echo "<p><b>Target:</b> $(printf '%s' "$TARGET" | html_escape) <br><b>Mode:</b> $(printf '%s' "$MODE" | html_escape)</p>"

  echo "<h2>Subdomains</h2><pre>"
  html_escape < "$SUB_ALL"
  echo "</pre>"

  echo "<h2>DNS (A)</h2><pre>"; html_escape < "$DNS_A"; echo "</pre>"
  echo "<h2>DNS (AAAA)</h2><pre>"; html_escape < "$DNS_AAAA"; echo "</pre>"
  echo "<h2>DNS (CNAME)</h2><pre>"; html_escape < "$DNS_CNAME"; echo "</pre>"

  echo "<h2>Alive (httpx)</h2><pre>"
  if [[ -s "$ALIVE" ]]; then html_escape < "$ALIVE"; else echo "(empty)"; fi
  echo "</pre>"

  echo "<h2>Crawl (katana)</h2><pre>"
  if [[ -s "$CRAWL" ]]; then html_escape < "$CRAWL"; else echo "(empty)"; fi
  echo "</pre>"

  echo "<h2>Nuclei</h2><pre>"
  if [[ -s "$NUCLEI_OUT" ]]; then html_escape < "$NUCLEI_OUT"; else echo "(empty)"; fi
  echo "</pre>"

  for f in waf.txt whatweb.txt tls.txt; do
    if [[ -s "${SCANDIR}/${f}" ]]; then
      echo "<h2>${f}</h2><pre>"
      html_escape < "${SCANDIR}/${f}"
      echo "</pre>"
    fi
  done

  echo "<hr><p><small>by The IT Bear • Memento Mori</small></p>"
  echo "</body></html>"
} > "$REPORT"

info "Done."
info "Report: ${REPORT}"

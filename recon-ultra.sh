#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ─── Color support ──────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]; then
  C_RESET="\033[0m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_RED="\033[31m"
  C_ORANGE="\033[38;5;202m"
  C_WHITE="\033[97m"
  C_DIM="\033[2m"
  C_BOLD="\033[1m"
else
  C_RESET="" C_GREEN="" C_YELLOW="" C_RED=""
  C_ORANGE="" C_WHITE="" C_DIM="" C_BOLD=""
fi

# ─── Logging ────────────────────────────────────────────────────────────────
_ts()  { date '+%H:%M:%S'; }
info() { printf "${C_GREEN}[+]${C_RESET} ${C_DIM}%s${C_RESET} %s\n"  "$(_ts)" "$*"; }
warn() { printf "${C_YELLOW}[!]${C_RESET} ${C_DIM}%s${C_RESET} %s\n" "$(_ts)" "$*" >&2; }
die()  { printf "${C_RED}[x]${C_RESET} ${C_DIM}%s${C_RESET} %s\n"    "$(_ts)" "$*" >&2; exit 1; }
step() { printf "\n${C_ORANGE}[>]${C_RESET} ${C_BOLD}%s${C_RESET}\n"  "$*"; }

# ─── Helpers ────────────────────────────────────────────────────────────────
need()    { command -v "$1" >/dev/null 2>&1; }
require() { need "$1" || die "Dipendenza mancante: $1"; }

html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# Returns true if file exists, has content, and --force is not set
_cached() { [[ "${FORCE:-0}" -eq 0 && -s "$1" ]]; }

# ─── Banner ─────────────────────────────────────────────────────────────────
banner_itbear() {
  [[ "${QUIET:-0}" == "1" ]] && return 0
  [[ -t 1 ]] || return 0

  local W SEP
  W=$(tput cols 2>/dev/null || echo 80)
  SEP=$(printf "%${W}s" | tr ' ' '=')

  clear
  printf "\n${C_ORANGE}%s${C_RESET}\n\n" "$SEP"

  printf "  ${C_ORANGE}o(^.^)o${C_RESET}  ${C_WHITE}${C_BOLD}RECON ULTRA${C_RESET}  ${C_ORANGE}o(^.^)o${C_RESET}\n\n"

  printf "${C_WHITE}"
  cat <<'ART'
  ██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
  ██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
  ██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
  ██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
  ██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
  ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝

  ██╗   ██╗██╗  ████████╗██████╗  █████╗
  ██║   ██║██║  ╚══██╔══╝██╔══██╗██╔══██╗
  ██║   ██║██║     ██║   ██████╔╝███████║
  ██║   ██║██║     ██║   ██╔══██╗██╔══██║
  ╚██████╔╝███████╗██║   ██║  ██║██║  ██║
   ╚═════╝ ╚══════╝╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝
ART
  printf "${C_RESET}\n"

  printf "  ${C_ORANGE}Passive ${C_WHITE}|${C_ORANGE} Light ${C_WHITE}|${C_ORANGE} Active  •  Kali-only${C_RESET}\n"
  printf "  ${C_DIM}by The IT Bear  •  Memento Mori  •  Use ONLY on assets you own or are authorized to test.${C_RESET}\n\n"

  printf "${C_ORANGE}%s${C_RESET}\n\n" "$SEP"
}

# ─── Usage ──────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage:
  $0 -t <target> [--passive|--light|--active] [options]

Options:
  -t, --target      Target domain (e.g. example.com)
  -o, --out         Output directory (default: ./out/<target>)
  --passive         Only passive OSINT (no active probing)
  --light           Low-noise enumeration (default)
  --active          Full pipeline (WAF, nuclei, screenshots, TLS...)
  --no-brute        Disable DNS brute-force stage
  -w, --wordlist    Custom wordlist for DNS brute-force
  --rl-httpx N      httpx rate limit req/s (default: 50)
  --rl-katana N     katana rate limit req/s (default: 10)
  --rl-nuclei N     nuclei rate limit req/s (default: 10)
  --force           Overwrite cached output (disable resume)
  --quiet, -q       No banner
  -h, --help        Show this help

Modes:
  passive   crt.sh + subfinder + amass + WHOIS + DNS records
  light     passive + httpx + katana + wayback (default)
  active    light  + wafw00f + whatweb + testssl + nuclei + screenshots
EOF
}

# ─── Defaults ───────────────────────────────────────────────────────────────
TARGET=""
OUTDIR=""
MODE="light"
BRUTE=1
QUIET=0
FORCE=0
WORDLIST=""
RATELIMIT_HTTPX=50
RATELIMIT_KATANA=10
RATELIMIT_NUCLEI=10
TIMER_START=$(date +%s)

# ─── Arg parsing ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)   TARGET="${2:-}";              shift 2 ;;
    -o|--out)      OUTDIR="${2:-}";              shift 2 ;;
    --passive)     MODE="passive";               shift ;;
    --light)       MODE="light";                 shift ;;
    --active)      MODE="active";                shift ;;
    --no-brute)    BRUTE=0;                      shift ;;
    -w|--wordlist) WORDLIST="${2:-}";            shift 2 ;;
    --rl-httpx)    RATELIMIT_HTTPX="${2:-50}";   shift 2 ;;
    --rl-katana)   RATELIMIT_KATANA="${2:-10}";  shift 2 ;;
    --rl-nuclei)   RATELIMIT_NUCLEI="${2:-10}";  shift 2 ;;
    --force)       FORCE=1;                      shift ;;
    --quiet|-q)    QUIET=1;                      shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Argomento sconosciuto: $1 (usa -h)" ;;
  esac
done

[[ -n "$TARGET" ]] || { usage; exit 1; }

# ─── Banner & directories ───────────────────────────────────────────────────
banner_itbear

OUTDIR="${OUTDIR:-./out/${TARGET}}"
SUBDIR="${OUTDIR}/subdomains"
DNSDIR="${OUTDIR}/dns"
HTTPDIR="${OUTDIR}/http"
SCANDIR="${OUTDIR}/scan"
REPORTDIR="${OUTDIR}/report"
mkdir -p "$SUBDIR" "$DNSDIR" "$HTTPDIR" "$SCANDIR" "$REPORTDIR"

# ─── Dependencies ───────────────────────────────────────────────────────────
require bash
require curl
require dig

if [[ "$MODE" != "passive" ]]; then
  require jq
else
  need jq || warn "jq non presente: crt.sh sarà saltato."
fi

OPTIONAL_TOOLS=(subfinder amass dnsx httpx katana nuclei whatweb wafw00f testssl.sh gowitness gau waybackurls whois)
for _t in "${OPTIONAL_TOOLS[@]}"; do
  need "$_t" || warn "Tool mancante (fase verrà saltata): $_t"
done

# ─── Phase: Subdomains (passive) ────────────────────────────────────────────
SUB_ALL="${SUBDIR}/subdomains_all.txt"

phase_subdomains() {
  step "Enumerazione subdomains (passive)"
  if _cached "$SUB_ALL"; then
    info "Subdomains: cache ok ($(wc -l < "$SUB_ALL" | tr -d ' ') entries). Usa --force per rieseguire."
    return 0
  fi
  : > "$SUB_ALL"

  if need subfinder; then
    info "subfinder..."
    subfinder -d "$TARGET" -silent >> "$SUB_ALL" || true
  fi

  if need amass; then
    info "amass (passive)..."
    amass enum -passive -d "$TARGET" 2>/dev/null >> "$SUB_ALL" || true
  fi

  if need jq; then
    info "crt.sh (Certificate Transparency)..."
    curl -fsSL "https://crt.sh/?q=%25.${TARGET}&output=json" \
      | jq -r '.[].name_value' 2>/dev/null \
      | tr '\r' '\n' \
      | sed 's/\*\.//g' \
      | awk 'NF' >> "$SUB_ALL" || true
  else
    warn "Skip crt.sh: jq mancante"
  fi

  sort -u "$SUB_ALL" -o "$SUB_ALL"
  info "Subdomains raccolti: $(wc -l < "$SUB_ALL" | tr -d ' ')"
}

# ─── Phase: DNS brute-force ──────────────────────────────────────────────────
SUB_BRUTE="${SUBDIR}/subdomains_bruteforce.txt"

phase_dns_brute() {
  if [[ "$BRUTE" -eq 0 ]]; then
    info "DNS brute-force disabilitato (--no-brute)."
    return 0
  fi
  [[ "$MODE" == "passive" ]] && return 0
  [[ -s "$SUB_ALL" ]]        || return 0
  need dnsx                  || { warn "Skip brute: dnsx non presente"; return 0; }

  step "DNS brute-force"
  if _cached "$SUB_BRUTE"; then
    info "Brute-force: cache ok. Usa --force per rieseguire."
    return 0
  fi

  local WORDS
  if [[ -n "$WORDLIST" && -f "$WORDLIST" ]]; then
    WORDS="$WORDLIST"
    info "Wordlist esterna: $WORDLIST ($(wc -l < "$WORDLIST" | tr -d ' ') parole)"
  else
    WORDS="${SUBDIR}/words_builtin.txt"
    cat > "$WORDS" <<'WL'
admin
api
app
auth
beta
blog
cdn
ci
cms
dashboard
dev
docs
files
ftp
git
internal
jira
mail
media
old
portal
prod
shop
smtp
stage
static
test
upload
vpn
www
WL
    info "Wordlist builtin ($(wc -l < "$WORDS" | tr -d ' ') parole)"
  fi

  dnsx -d "$TARGET" -w "$WORDS" -silent 2>/dev/null | sort -u > "$SUB_BRUTE" || true

  if [[ -s "$SUB_BRUTE" ]]; then
    cat "$SUB_BRUTE" >> "$SUB_ALL"
    sort -u "$SUB_ALL" -o "$SUB_ALL"
    info "Nuovi subdomain da brute: $(wc -l < "$SUB_BRUTE" | tr -d ' ')"
  fi
}

# ─── Phase: DNS resolve (A / AAAA / CNAME) ──────────────────────────────────
DNS_A="${DNSDIR}/A.txt"
DNS_AAAA="${DNSDIR}/AAAA.txt"
DNS_CNAME="${DNSDIR}/CNAME.txt"

phase_dns_resolve() {
  step "Risoluzione DNS (A / AAAA / CNAME)"
  if _cached "$DNS_A"; then
    info "DNS resolve: cache ok. Usa --force per rieseguire."
    return 0
  fi
  : > "$DNS_A"; : > "$DNS_AAAA"; : > "$DNS_CNAME"

  if need dnsx; then
    info "dnsx bulk resolution..."
    dnsx -l "$SUB_ALL" -silent -a     -resp 2>/dev/null | tr -d '[]' | awk '{print $1, $NF}' >> "$DNS_A"     || true
    dnsx -l "$SUB_ALL" -silent -aaaa  -resp 2>/dev/null | tr -d '[]' | awk '{print $1, $NF}' >> "$DNS_AAAA"  || true
    dnsx -l "$SUB_ALL" -silent -cname -resp 2>/dev/null | tr -d '[]' | awk '{print $1, $NF}' >> "$DNS_CNAME" || true
  else
    local TOTAL N=0
    TOTAL=$(wc -l < "$SUB_ALL" | tr -d ' ')
    while read -r sub; do
      [[ -z "$sub" ]] && continue
      N=$(( N + 1 ))
      printf '\r  %s[%d/%d]%s %-55.55s' "${C_DIM}" "$N" "$TOTAL" "${C_RESET}" "$sub"
      dig +short A     "$sub" | awk -v h="$sub" 'NF{print h, $0}' >> "$DNS_A"    || true
      dig +short AAAA  "$sub" | awk -v h="$sub" 'NF{print h, $0}' >> "$DNS_AAAA" || true
      dig +short CNAME "$sub" | awk -v h="$sub" 'NF{print h, $0}' >> "$DNS_CNAME"|| true
    done < "$SUB_ALL"
    printf '\n'
  fi

  sort -u "$DNS_A" -o "$DNS_A"
  sort -u "$DNS_AAAA" -o "$DNS_AAAA"
  sort -u "$DNS_CNAME" -o "$DNS_CNAME"
  info "A: $(wc -l < "$DNS_A" | tr -d ' ')  AAAA: $(wc -l < "$DNS_AAAA" | tr -d ' ')  CNAME: $(wc -l < "$DNS_CNAME" | tr -d ' ')"
}

# ─── Phase: DNS extras (MX, NS, TXT, SPF, DMARC, DKIM) ─────────────────────
DNS_MX="${DNSDIR}/MX.txt"
DNS_NS="${DNSDIR}/NS.txt"
DNS_TXT="${DNSDIR}/TXT.txt"

phase_dns_extras() {
  step "DNS extras (MX, NS, TXT, SPF, DMARC, DKIM)"
  if _cached "$DNS_MX"; then
    info "DNS extras: cache ok. Usa --force per rieseguire."
    return 0
  fi
  : > "$DNS_MX"; : > "$DNS_NS"; : > "$DNS_TXT"

  dig +short MX  "$TARGET"                        > "$DNS_MX"  || true
  dig +short NS  "$TARGET"                        > "$DNS_NS"  || true
  dig +short TXT "$TARGET"                       >> "$DNS_TXT" || true
  dig +short TXT "_dmarc.${TARGET}"              >> "$DNS_TXT" || true
  dig +short TXT "mail._domainkey.${TARGET}"     >> "$DNS_TXT" || true
  dig +short TXT "default._domainkey.${TARGET}"  >> "$DNS_TXT" || true

  info "MX: $(wc -l < "$DNS_MX" | tr -d ' ')  NS: $(wc -l < "$DNS_NS" | tr -d ' ')  TXT: $(wc -l < "$DNS_TXT" | tr -d ' ')"
}

# ─── Phase: WHOIS ───────────────────────────────────────────────────────────
WHOIS_OUT="${SCANDIR}/whois.txt"

phase_whois() {
  step "WHOIS"
  need whois || { warn "Skip WHOIS: whois non presente"; : > "$WHOIS_OUT"; return 0; }
  if _cached "$WHOIS_OUT"; then
    info "WHOIS: cache ok. Usa --force per rieseguire."
    return 0
  fi
  whois "$TARGET" 2>/dev/null > "$WHOIS_OUT" || true
  info "WHOIS: $(wc -l < "$WHOIS_OUT" | tr -d ' ') righe"
}

# ─── Phase: HTTP probing ────────────────────────────────────────────────────
HOSTS="${HTTPDIR}/hosts.txt"
ALIVE="${HTTPDIR}/alive.txt"

phase_http_probe() {
  cp "$SUB_ALL" "$HOSTS"

  if [[ "$MODE" == "passive" ]]; then
    info "Mode passive: skip HTTP probe."
    : > "$ALIVE"
    return 0
  fi
  if [[ ! -s "$HOSTS" ]]; then
    warn "Nessun host da testare."
    : > "$ALIVE"
    return 0
  fi
  if ! need httpx; then
    warn "Skip httpx: non presente"
    : > "$ALIVE"
    return 0
  fi

  step "HTTP probing (httpx, rate-limit ${RATELIMIT_HTTPX}/s)"
  if _cached "$ALIVE"; then
    info "HTTP probe: cache ok ($(wc -l < "$ALIVE" | tr -d ' ') host alive). Usa --force per rieseguire."
    return 0
  fi
  : > "$ALIVE"
  httpx -l "$HOSTS" -silent -rl "$RATELIMIT_HTTPX" -title -tech-detect -status-code \
    | tee "$ALIVE" >/dev/null || true
  info "Host alive: $(wc -l < "$ALIVE" | tr -d ' ')"
}

# ─── Phase: Fingerprint (WAF, WhatWeb, TLS) ─────────────────────────────────
phase_fingerprint() {
  [[ "$MODE" == "active" ]] || return 0
  [[ -s "$ALIVE" ]]         || return 0

  step "Fingerprint (WAF, WhatWeb, TLS)"

  if need wafw00f && ! _cached "${SCANDIR}/waf.txt"; then
    info "wafw00f (prime 50 URL)..."
    awk '{print $1}' "$ALIVE" | head -50 | while read -r url; do
      wafw00f "$url" 2>/dev/null || true
    done > "${SCANDIR}/waf.txt"
  fi

  if need whatweb && ! _cached "${SCANDIR}/whatweb.txt"; then
    info "whatweb (prime 50 URL)..."
    awk '{print $1}' "$ALIVE" | head -50 | while read -r url; do
      whatweb --no-errors "$url" 2>/dev/null || true
    done > "${SCANDIR}/whatweb.txt"
  fi

  if need testssl.sh && ! _cached "${SCANDIR}/tls.txt"; then
    info "testssl.sh (prime 10 HTTPS)..."
    awk '{print $1}' "$ALIVE" | grep -E '^https://' | head -10 | while read -r url; do
      testssl.sh --quiet "$url" 2>/dev/null || true
    done > "${SCANDIR}/tls.txt"
  fi
}

# ─── Phase: Wayback Machine / URL discovery ─────────────────────────────────
WAY_OUT="${SCANDIR}/wayback.txt"

phase_wayback() {
  if [[ "$MODE" == "passive" ]]; then
    : > "$WAY_OUT"
    return 0
  fi

  step "Wayback Machine / URL discovery"
  if _cached "$WAY_OUT"; then
    info "Wayback: cache ok ($(wc -l < "$WAY_OUT" | tr -d ' ') URL). Usa --force per rieseguire."
    return 0
  fi
  : > "$WAY_OUT"

  if need gau; then
    info "gau..."
    gau --threads 2 "$TARGET" 2>/dev/null | sort -u > "$WAY_OUT" || true
  elif need waybackurls; then
    info "waybackurls..."
    echo "$TARGET" | waybackurls 2>/dev/null | sort -u > "$WAY_OUT" || true
  else
    info "Wayback CDX API (fallback curl)..."
    curl -fsSL \
      "https://web.archive.org/cdx/search/cdx?url=*.${TARGET}/*&output=text&fl=original&collapse=urlkey&limit=2000" \
      2>/dev/null | sort -u > "$WAY_OUT" || true
  fi
  info "URL da Wayback: $(wc -l < "$WAY_OUT" | tr -d ' ')"
}

# ─── Phase: Crawl ───────────────────────────────────────────────────────────
CRAWL="${SCANDIR}/crawl.txt"

phase_crawl() {
  if [[ "$MODE" == "passive" ]]; then
    : > "$CRAWL"
    return 0
  fi
  if [[ ! -s "$ALIVE" ]]; then
    : > "$CRAWL"
    return 0
  fi
  if ! need katana; then
    warn "Skip katana: non presente"
    : > "$CRAWL"
    return 0
  fi

  step "Crawl (katana, rate-limit ${RATELIMIT_KATANA}/s)"
  if _cached "$CRAWL"; then
    info "Crawl: cache ok ($(wc -l < "$CRAWL" | tr -d ' ') URL). Usa --force per rieseguire."
    return 0
  fi
  : > "$CRAWL"
  awk '{print $1}' "$ALIVE" | head -100 \
    | katana -silent -rl "$RATELIMIT_KATANA" -d 2 2>/dev/null \
    | sort -u > "$CRAWL" || true
  info "URL crawled: $(wc -l < "$CRAWL" | tr -d ' ')"
}

# ─── Phase: Nuclei ──────────────────────────────────────────────────────────
NUCLEI_OUT="${SCANDIR}/nuclei.txt"

phase_nuclei() {
  if [[ "$MODE" != "active" ]]; then
    info "Mode non active: skip nuclei."
    : > "$NUCLEI_OUT"
    return 0
  fi
  if [[ ! -s "$ALIVE" ]]; then
    : > "$NUCLEI_OUT"
    return 0
  fi
  if ! need nuclei; then
    warn "Skip nuclei: non presente"
    : > "$NUCLEI_OUT"
    return 0
  fi

  step "Nuclei scan (rate-limit ${RATELIMIT_NUCLEI}/s)"
  if _cached "$NUCLEI_OUT"; then
    info "Nuclei: cache ok ($(wc -l < "$NUCLEI_OUT" | tr -d ' ') finding). Usa --force per rieseguire."
    return 0
  fi
  : > "$NUCLEI_OUT"
  awk '{print $1}' "$ALIVE" \
    | nuclei -silent -rl "$RATELIMIT_NUCLEI" 2>/dev/null \
    | tee "$NUCLEI_OUT" >/dev/null || true
  info "Findings nuclei: $(wc -l < "$NUCLEI_OUT" | tr -d ' ')"
}

# ─── Phase: Screenshots (gowitness) ─────────────────────────────────────────
SHOTS_DIR="${SCANDIR}/screenshots"

phase_screenshots() {
  [[ "$MODE" == "active" ]] || return 0
  [[ -s "$ALIVE" ]]         || return 0
  need gowitness            || { warn "Skip screenshots: gowitness non presente"; return 0; }

  step "Screenshots (gowitness, prime 50 URL)"
  mkdir -p "$SHOTS_DIR"
  local TMP="${SHOTS_DIR}/.urls.tmp"
  awk '{print $1}' "$ALIVE" | head -50 > "$TMP"
  gowitness file -f "$TMP" -P "$SHOTS_DIR" --timeout 10 2>/dev/null || true
  rm -f "$TMP"
  info "Screenshot in: $SHOTS_DIR"
}

# ─── Phase: Report (HTML + JSON) ────────────────────────────────────────────
REPORT="${REPORTDIR}/report.html"
REPORT_JSON="${REPORTDIR}/report.json"

phase_report() {
  step "Genero report (HTML + JSON)"

  local ELAPSED TS SUB_COUNT ALIVE_COUNT NUCLEI_COUNT WAY_COUNT
  ELAPSED=$(( $(date +%s) - TIMER_START ))
  TS=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
  SUB_COUNT=$(wc -l < "$SUB_ALL" | tr -d ' ')
  ALIVE_COUNT=0;   [[ -s "$ALIVE" ]]      && ALIVE_COUNT=$(wc -l < "$ALIVE" | tr -d ' ')
  NUCLEI_COUNT=0;  [[ -s "$NUCLEI_OUT" ]] && NUCLEI_COUNT=$(wc -l < "$NUCLEI_OUT" | tr -d ' ')
  WAY_COUNT=0;     [[ -s "$WAY_OUT" ]]    && WAY_COUNT=$(wc -l < "$WAY_OUT" | tr -d ' ')

  # ── JSON ────────────────────────────────────────────────────────────────
  {
    printf '{\n'
    printf '  "target": "%s",\n'           "$TARGET"
    printf '  "mode": "%s",\n'             "$MODE"
    printf '  "timestamp": "%s",\n'        "$TS"
    printf '  "duration_seconds": %d,\n'   "$ELAPSED"
    printf '  "stats": {\n'
    printf '    "subdomains": %s,\n'       "$SUB_COUNT"
    printf '    "alive_hosts": %s,\n'      "$ALIVE_COUNT"
    printf '    "nuclei_findings": %s,\n'  "$NUCLEI_COUNT"
    printf '    "wayback_urls": %s\n'      "$WAY_COUNT"
    printf '  }\n}\n'
  } > "$REPORT_JSON"

  # ── HTML ────────────────────────────────────────────────────────────────
  {
    cat <<'HTMLHEAD'
<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<title>Recon-Ultra Report</title>
<style>
  :root{
    --bg:#0d1117;--bg2:#161b22;--border:#30363d;
    --text:#e6edf3;--dim:#8b949e;
    --orange:#f97316;--green:#3fb950;--red:#f85149;--yellow:#d29922;
  }
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,Arial,sans-serif;font-size:14px;line-height:1.6;padding:24px}
  h1{color:var(--orange);font-size:1.8rem;margin-bottom:6px}
  h2{color:var(--orange);font-size:1rem;font-weight:600;margin:28px 0 8px;padding-bottom:4px;border-bottom:1px solid var(--border)}
  pre{background:var(--bg2);color:var(--text);padding:14px;overflow:auto;border-radius:8px;border:1px solid var(--border);font-size:12px;font-family:'Cascadia Code','Fira Mono',monospace;white-space:pre-wrap;word-break:break-all}
  .meta{color:var(--dim);font-size:.85rem;margin-bottom:4px}
  .stats{display:flex;gap:14px;flex-wrap:wrap;margin:18px 0}
  .stat{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:12px 22px;text-align:center}
  .stat .n{font-size:2rem;font-weight:700;color:var(--orange)}
  .stat .l{font-size:.75rem;color:var(--dim);text-transform:uppercase;letter-spacing:.06em}
  .empty{color:var(--dim);font-style:italic}
  footer{margin-top:40px;padding-top:16px;border-top:1px solid var(--border);color:var(--dim);font-size:.8rem}
</style>
</head>
<body>
HTMLHEAD

    printf '<h1>Recon-Ultra Report</h1>\n'
    printf '<p class="meta"><b>Target:</b> %s</p>\n' "$(printf '%s' "$TARGET" | html_escape)"
    printf '<p class="meta"><b>Mode:</b> %s &nbsp;•&nbsp; <b>Date:</b> %s &nbsp;•&nbsp; <b>Duration:</b> %ds</p>\n' \
      "$(printf '%s' "$MODE" | html_escape)" "$(printf '%s' "$TS" | html_escape)" "$ELAPSED"

    printf '<div class="stats">\n'
    printf '  <div class="stat"><div class="n">%s</div><div class="l">Subdomains</div></div>\n' "$SUB_COUNT"
    printf '  <div class="stat"><div class="n">%s</div><div class="l">Alive Hosts</div></div>\n' "$ALIVE_COUNT"
    printf '  <div class="stat"><div class="n">%s</div><div class="l">Wayback URLs</div></div>\n' "$WAY_COUNT"
    printf '  <div class="stat"><div class="n">%s</div><div class="l">Nuclei Findings</div></div>\n' "$NUCLEI_COUNT"
    printf '</div>\n'

    _section() {
      local title="$1" file="$2"
      printf '<h2>%s</h2><pre>' "$(printf '%s' "$title" | html_escape)"
      if [[ -s "$file" ]]; then html_escape < "$file"; else printf '<span class="empty">(vuoto)</span>'; fi
      printf '</pre>\n'
    }

    _section "Subdomains (${SUB_COUNT})" "$SUB_ALL"
    _section "DNS — Record A"     "$DNS_A"
    _section "DNS — Record AAAA"  "$DNS_AAAA"
    _section "DNS — Record CNAME" "$DNS_CNAME"

    printf '<h2>DNS — MX / NS / TXT / SPF / DMARC / DKIM</h2>\n'
    for f in MX.txt NS.txt TXT.txt; do
      [[ -s "${DNSDIR}/${f}" ]] || continue
      printf '<b>%s</b><pre>' "$f"
      html_escape < "${DNSDIR}/${f}"
      printf '</pre>\n'
    done

    _section "WHOIS"                         "$WHOIS_OUT"
    _section "Alive Hosts — httpx (${ALIVE_COUNT})" "$ALIVE"
    _section "Wayback URLs (${WAY_COUNT})"   "$WAY_OUT"
    _section "Crawl — katana"                "$CRAWL"
    _section "Nuclei Findings (${NUCLEI_COUNT})" "$NUCLEI_OUT"

    for f in waf.txt whatweb.txt tls.txt; do
      [[ -s "${SCANDIR}/${f}" ]] && _section "$f" "${SCANDIR}/${f}"
    done

    printf '<footer>by The IT Bear &nbsp;&bull;&nbsp; Memento Mori &nbsp;&bull;&nbsp; Use ONLY on assets you own or are authorized to test.</footer>\n'
    printf '</body></html>\n'
  } > "$REPORT"

  info "HTML  → ${REPORT}"
  info "JSON  → ${REPORT_JSON}"
}

# ─── Main pipeline ───────────────────────────────────────────────────────────
phase_subdomains
phase_dns_brute
phase_dns_resolve
phase_dns_extras
phase_whois
phase_http_probe
phase_fingerprint
phase_wayback
phase_crawl
phase_nuclei
phase_screenshots
phase_report

step "Done"
info "Output directory: ${OUTDIR}"
info "Durata totale: $(( $(date +%s) - TIMER_START ))s"

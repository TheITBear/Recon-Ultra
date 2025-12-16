#!/usr/bin/env bash
# =====================================================================
# Recon ULTRA - Red Team Edition (stealth-ish, OSINT + passive/active light)
# by The ITBear
# =====================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# -------------------------
# Defaults
# -------------------------
MODE="light"               # passive | light | active
THREADS=20
OUTDIR=""
TARGET=""
DO_REPORT=1
DO_BRUTE=1
KATANA_DEPTH=2
NUCLEI_RATE=3              # requests/second (best effort)
SLEEP_MIN=1
SLEEP_MAX=3
TINYLIST_DEFAULT="/usr/share/seclists/Discovery/DNS/subdomains-top1million-20000.txt"

# -------------------------
# Helpers
# -------------------------
die(){ echo "[!] $*" >&2; exit 1; }
info(){ echo "[*] $*"; }
ok(){ echo "[✓] $*"; }
warn(){ echo "[!] $*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || return 1; }

rand_ua() {
  shuf -n 1 <<'EOF'
Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)
Mozilla/5.0 (X11; Ubuntu; Linux x86_64)
Mozilla/5.0 (X11; Linux; rv:102.0)
EOF
}

rand_wait() {
  sleep "$(shuf -i "${SLEEP_MIN}-${SLEEP_MAX}" -n 1)"
}

html_escape() {
  # escape &, <, > to keep report valid
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

usage() {
  cat <<EOF
Uso: $0 -d dominio [opzioni]

Modalità:
  --passive            Solo OSINT + subdomain passive + DNS resolve (default: --light)
  --light              Passive + fingerprinting + alive hosts + crawl light
  --active             Come light + nuclei (rate-limited) + opzionale TLS checks

Opzioni:
  -d, --domain DOMAIN  Target domain (es: example.com)
  -o, --out DIR        Directory output (default: out-<domain>-YYYYmmdd_HHMMSS)
  -t, --threads N      Concorrenza (default: 20) [usata dove applicabile]
  --no-report          Non generare report HTML
  --no-brute           Disabilita dns brute-force (dnsx wordlist)
  --wordlist PATH      Wordlist per dnsx (default: ${TINYLIST_DEFAULT})
  --katana-depth N     Profondità katana (default: 2)
  --nuclei-rate N      Rate nuclei (req/sec, best effort) (default: 3)

Esempi:
  $0 -d example.com --passive
  $0 -d example.com --light
  $0 -d example.com --active --no-brute
EOF
}

WORDLIST="$TINYLIST_DEFAULT"

# -------------------------
# Args
# -------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain) TARGET="${2:-}"; shift 2;;
    -o|--out) OUTDIR="${2:-}"; shift 2;;
    -t|--threads) THREADS="${2:-}"; shift 2;;
    --passive) MODE="passive"; shift;;
    --light) MODE="light"; shift;;
    --active) MODE="active"; shift;;
    --no-report) DO_REPORT=0; shift;;
    --no-brute) DO_BRUTE=0; shift;;
    --wordlist) WORDLIST="${2:-}"; shift 2;;
    --katana-depth) KATANA_DEPTH="${2:-}"; shift 2;;
    --nuclei-rate) NUCLEI_RATE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Argomento sconosciuto: $1 (usa --help)";;
  esac
done

[[ -n "$TARGET" ]] || { usage; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
if [[ -z "$OUTDIR" ]]; then
  OUTDIR="out-${TARGET}-${TS}"
fi

# normalize OUTDIR (avoid weird chars)
OUTDIR="${OUTDIR// /_}"

mkdir -p "$OUTDIR"/{osint,subdomains,dns,http,crawl,scan,meta}

UA="$(rand_ua)"

# -------------------------
# Dependency checks (soft)
# -------------------------
REQ_ALWAYS=(whois curl jq dig sort)
for c in "${REQ_ALWAYS[@]}"; do
  need "$c" || die "Dipendenza mancante: $c"
done

# Optional tools by mode
HAS_SUBFINDER=0; need subfinder && HAS_SUBFINDER=1
HAS_AMASS=0; need amass && HAS_AMASS=1
HAS_DNSX=0; need dnsx && HAS_DNSX=1
HAS_HTTPX=0; need httpx && HAS_HTTPX=1
HAS_WAFW00F=0; need wafw00f && HAS_WAFW00F=1
HAS_WHATWEB=0; need whatweb && HAS_WHATWEB=1
HAS_KATANA=0; need katana && HAS_KATANA=1
HAS_NUCLEI=0; need nuclei && HAS_NUCLEI=1
HAS_TESTSSL=0; need testssl.sh && HAS_TESTSSL=1

info "Recon ULTRA – Target: ${TARGET}"
info "Mode: ${MODE}"
info "Output: ${OUTDIR}"
info "UA: ${UA}"
echo "==================================================================="

# -------------------------
# 0) Passive OSINT
# -------------------------
info "OSINT: WHOIS"
whois "$TARGET" > "${OUTDIR}/osint/whois.txt" 2>/dev/null || true
rand_wait

info "OSINT: Certificate Transparency (crt.sh)"
# crt.sh JSON can contain multiline name_value; normalize and drop wildcards
curl -s -A "$UA" "https://crt.sh/?q=%25.${TARGET}&output=json" \
  | jq -r '.[].name_value' 2>/dev/null \
  | tr '\r' '\n' \
  | sed 's/\*\.//g' \
  | awk 'NF' \
  | sort -u > "${OUTDIR}/osint/crt.txt" || true
rand_wait

# -------------------------
# 1) Subdomain Enumeration (passive + optional brute)
# -------------------------
info "Subdomain Enumeration (passive)"
: > "${OUTDIR}/subdomains/subs_raw.txt"

if [[ $HAS_SUBFINDER -eq 1 ]]; then
  subfinder -silent -d "$TARGET" >> "${OUTDIR}/subdomains/subs_raw.txt" || true
else
  warn "subfinder non trovato: salto"
fi

if [[ $HAS_AMASS -eq 1 ]]; then
  amass enum -passive -d "$TARGET" >> "${OUTDIR}/subdomains/subs_raw.txt" 2>/dev/null || true
else
  warn "amass non trovato: salto"
fi

cat "${OUTDIR}/osint/crt.txt" >> "${OUTDIR}/subdomains/subs_raw.txt" 2>/dev/null || true

if [[ "$DO_BRUTE" -eq 1 ]]; then
  if [[ $HAS_DNSX -eq 1 ]]; then
    [[ -f "$WORDLIST" ]] || { warn "Wordlist non trovata: $WORDLIST (brute disabilitato)"; DO_BRUTE=0; }
    if [[ "$DO_BRUTE" -eq 1 ]]; then
      info "DNS brute-force (dnsx) – wordlist: $WORDLIST"
      dnsx -d "$TARGET" -w "$WORDLIST" -silent >> "${OUTDIR}/subdomains/subs_raw.txt" 2>/dev/null || true
    fi
  else
    warn "dnsx non trovato: brute disabilitato"
  fi
else
  info "DNS brute-force disabilitato (--no-brute)"
fi

sort -u "${OUTDIR}/subdomains/subs_raw.txt" | awk 'NF' > "${OUTDIR}/subdomains/subdomains.txt"
ok "Subdomains: $(wc -l < "${OUTDIR}/subdomains/subdomains.txt" | tr -d ' ')"
rand_wait

# -------------------------
# 2) DNS Resolution (A/AAAA/CNAME)
# -------------------------
info "DNS resolving (A/AAAA/CNAME)"
: > "${OUTDIR}/dns/a.txt"
: > "${OUTDIR}/dns/aaaa.txt"
: > "${OUTDIR}/dns/cname.txt"
: > "${OUTDIR}/dns/unresolved.txt"

while IFS= read -r sub; do
  [[ -n "$sub" ]] || continue

  a_records="$(dig +short A "$sub" | tr '\r' '\n' | awk 'NF' || true)"
  aaaa_records="$(dig +short AAAA "$sub" | tr '\r' '\n' | awk 'NF' || true)"
  cname_records="$(dig +short CNAME "$sub" | tr '\r' '\n' | awk 'NF' || true)"

  if [[ -n "$a_records" ]]; then
    while IFS= read -r ip; do echo "${sub} ${ip}" >> "${OUTDIR}/dns/a.txt"; done <<< "$a_records"
  fi
  if [[ -n "$aaaa_records" ]]; then
    while IFS= read -r ip; do echo "${sub} ${ip}" >> "${OUTDIR}/dns/aaaa.txt"; done <<< "$aaaa_records"
  fi
  if [[ -n "$cname_records" ]]; then
    while IFS= read -r cn; do echo "${sub} ${cn}" >> "${OUTDIR}/dns/cname.txt"; done <<< "$cname_records"
  fi

  if [[ -z "$a_records" && -z "$aaaa_records" && -z "$cname_records" ]]; then
    echo "$sub" >> "${OUTDIR}/dns/unresolved.txt"
  fi
done < "${OUTDIR}/subdomains/subdomains.txt"

ok "Resolved A: $(wc -l < "${OUTDIR}/dns/a.txt" | tr -d ' ') | AAAA: $(wc -l < "${OUTDIR}/dns/aaaa.txt" | tr -d ' ') | CNAME: $(wc -l < "${OUTDIR}/dns/cname.txt" | tr -d ' ')"
rand_wait

# -------------------------
# 3) HTTP alive (recommended) + fingerprinting (light/active)
# -------------------------
if [[ "$MODE" != "passive" ]]; then
  info "HTTP alive discovery"
  if [[ $HAS_HTTPX -eq 1 ]]; then
    cat "${OUTDIR}/subdomains/subdomains.txt" \
      | httpx -silent -no-color -threads "$THREADS" -timeout 10 -retries 2 \
      > "${OUTDIR}/http/alive.txt" || true
  else
    warn "httpx non trovato: uso fallback (https://TARGET)"
    echo "https://${TARGET}" > "${OUTDIR}/http/alive.txt"
  fi
  ok "Alive URLs: $(wc -l < "${OUTDIR}/http/alive.txt" | tr -d ' ')"
  rand_wait

  info "Headers snapshot"
  # Grab headers from the apex domain (cheap) + first 20 alive URLs (avoid being noisy)
  {
    echo "=== https://${TARGET} ==="
    curl -s -A "$UA" -I "https://${TARGET}" || true
    echo
    head -n 20 "${OUTDIR}/http/alive.txt" | while IFS= read -r url; do
      echo "=== ${url} ==="
      curl -s -A "$UA" -I "$url" || true
      echo
    done
  } > "${OUTDIR}/http/headers.txt"
  rand_wait

  if [[ $HAS_WHATWEB -eq 1 ]]; then
    info "WhatWeb (brief)"
    whatweb --log-brief="${OUTDIR}/http/whatweb.txt" "$TARGET" >/dev/null 2>&1 || true
  else
    warn "whatweb non trovato: salto"
    : > "${OUTDIR}/http/whatweb.txt"
  fi

  if [[ $HAS_WAFW00F -eq 1 ]]; then
    info "WAF/CDN fingerprint (wafw00f)"
    wafw00f "$TARGET" > "${OUTDIR}/http/waf.txt" 2>/dev/null || true
  else
    warn "wafw00f non trovato: salto"
    : > "${OUTDIR}/http/waf.txt"
  fi
fi

# -------------------------
# 4) Reverse IP / Virtual Hosts (best-effort)
# -------------------------
info "Reverse IP (best-effort)"
IP="$(dig +short A "$TARGET" | head -n 1 || true)"
if [[ -n "${IP:-}" ]]; then
  curl -s -A "$UA" "https://api.hackertarget.com/reverseiplookup/?q=${IP}" \
    > "${OUTDIR}/osint/reverse_ip.txt" || true
else
  echo "No A record found for apex domain." > "${OUTDIR}/osint/reverse_ip.txt"
fi
rand_wait

# -------------------------
# 5) Crawl (light/active)
# -------------------------
if [[ "$MODE" != "passive" ]]; then
  if [[ $HAS_KATANA -eq 1 ]]; then
    info "Crawling (katana depth=${KATANA_DEPTH})"
    # Crawl only a small set to reduce noise
    head -n 20 "${OUTDIR}/http/alive.txt" | while IFS= read -r url; do
      katana -u "$url" -silent -d "$KATANA_DEPTH" -jc -jsl -kf -ps \
        >> "${OUTDIR}/crawl/crawl.txt" 2>/dev/null || true
    done
    sort -u "${OUTDIR}/crawl/crawl.txt" -o "${OUTDIR}/crawl/crawl.txt" 2>/dev/null || true
  else
    warn "katana non trovato: salto crawl"
    : > "${OUTDIR}/crawl/crawl.txt"
  fi
  rand_wait
fi

# -------------------------
# 6) Active checks (nuclei + optional TLS)
# -------------------------
if [[ "$MODE" == "active" ]]; then
  if [[ $HAS_NUCLEI -eq 1 ]]; then
    info "Nuclei (rate-limited best effort: ${NUCLEI_RATE} req/s)"
    # Use only low/med by default to avoid being too loud; user can tweak templates locally.
    nuclei -l "${OUTDIR}/http/alive.txt" \
      -severity low,medium \
      -rl "$NUCLEI_RATE" \
      -timeout 10 -retries 1 -silent \
      > "${OUTDIR}/scan/nuclei.txt" 2>/dev/null || true
  else
    warn "nuclei non trovato: salto"
    : > "${OUTDIR}/scan/nuclei.txt"
  fi

  if [[ $HAS_TESTSSL -eq 1 ]]; then
    info "TLS/SSL check (testssl.sh) – apex only"
    testssl.sh --quiet "https://${TARGET}" > "${OUTDIR}/scan/ssl.txt" 2>/dev/null || true
  else
    warn "testssl.sh non trovato: salto"
    : > "${OUTDIR}/scan/ssl.txt"
  fi
fi

# -------------------------
# 7) Report
# -------------------------
if [[ "$DO_REPORT" -eq 1 ]]; then
  info "Generating HTML report"
  REPORT="${OUTDIR}/report.html"

  # Ensure files exist
  touch "${OUTDIR}/http/waf.txt" "${OUTDIR}/http/whatweb.txt" "${OUTDIR}/http/headers.txt" \
        "${OUTDIR}/crawl/crawl.txt" "${OUTDIR}/scan/nuclei.txt" "${OUTDIR}/scan/ssl.txt" \
        "${OUTDIR}/osint/reverse_ip.txt"

  cat > "$REPORT" <<EOF
<html>
<head>
  <meta charset="utf-8">
  <title>Recon ULTRA Report - ${TARGET}</title>
  <style>
    body { font-family: Arial, sans-serif; background:#0e0e0e; color:#eaeaea; padding:20px; }
    h1,h2 { color:#ff4500; }
    pre { background:#111; border:1px solid #333; padding:10px; overflow:auto; }
    .meta { color:#aaa; font-size: 0.9em; }
  </style>
</head>
<body>

<h1>Recon ULTRA Report</h1>
<div class="meta">
  <b>Target:</b> ${TARGET}<br>
  <b>Mode:</b> ${MODE}<br>
  <b>Generated:</b> $(date)<br>
  <b>Output:</b> ${OUTDIR}
</div>

<h2>Subdomains (count)</h2>
<pre>$(wc -l < "${OUTDIR}/subdomains/subdomains.txt" | tr -d ' ')</pre>

<h2>Subdomains list</h2>
<pre>$(html_escape < "${OUTDIR}/subdomains/subdomains.txt")</pre>

<h2>DNS - A records</h2>
<pre>$(html_escape < "${OUTDIR}/dns/a.txt")</pre>

<h2>DNS - AAAA records</h2>
<pre>$(html_escape < "${OUTDIR}/dns/aaaa.txt")</pre>

<h2>DNS - CNAME records</h2>
<pre>$(html_escape < "${OUTDIR}/dns/cname.txt")</pre>

<h2>Unresolved</h2>
<pre>$(html_escape < "${OUTDIR}/dns/unresolved.txt")</pre>

<h2>Alive URLs</h2>
<pre>$(html_escape < "${OUTDIR}/http/alive.txt" 2>/dev/null || true)</pre>

<h2>WAF/CDN</h2>
<pre>$(html_escape < "${OUTDIR}/http/waf.txt")</pre>

<h2>WhatWeb</h2>
<pre>$(html_escape < "${OUTDIR}/http/whatweb.txt")</pre>

<h2>Headers snapshot</h2>
<pre>$(html_escape < "${OUTDIR}/http/headers.txt")</pre>

<h2>Reverse IP (best-effort)</h2>
<pre>$(html_escape < "${OUTDIR}/osint/reverse_ip.txt")</pre>

<h2>Crawl (katana)</h2>
<pre>$(html_escape < "${OUTDIR}/crawl/crawl.txt")</pre>

<h2>Nuclei (low/medium)</h2>
<pre>$(html_escape < "${OUTDIR}/scan/nuclei.txt")</pre>

<h2>SSL/TLS</h2>
<pre>$(html_escape < "${OUTDIR}/scan/ssl.txt")</pre>

</body>
</html>
EOF

  ok "Report: ${REPORT}"
else
  info "Report disabilitato (--no-report)"
fi

ok "Recon ULTRA completato."

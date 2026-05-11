# Recon-Ultra

**RECON ULTRA** is a Kali Linux–focused reconnaissance wrapper that combines passive OSINT and controlled active enumeration into clean, actionable outputs — an HTML dark-mode report and a structured JSON file.

> **Kali-only by design.** Other distros are intentionally out of scope to keep dependencies predictable.

---

## Features

| Feature | Passive | Light | Active |
|---------|:-------:|:-----:|:------:|
| Subdomain enumeration (subfinder, amass, crt.sh) | ✓ | ✓ | ✓ |
| DNS resolution (A / AAAA / CNAME) | ✓ | ✓ | ✓ |
| DNS extras (MX, NS, TXT, SPF, DMARC, DKIM) | ✓ | ✓ | ✓ |
| WHOIS (registrar, abuse contact, dates) | ✓ | ✓ | ✓ |
| DNS brute-force (dnsx) | — | ✓ | ✓ |
| Live host discovery (httpx + tech/title/status) | — | ✓ | ✓ |
| Wayback Machine / URL history (gau / waybackurls / CDX API) | — | ✓ | ✓ |
| Web crawling (katana) | — | ✓ | ✓ |
| WAF detection (wafw00f) | — | — | ✓ |
| Technology fingerprint (whatweb) | — | — | ✓ |
| TLS audit (testssl.sh) | — | — | ✓ |
| Vulnerability scan (nuclei) | — | — | ✓ |
| Screenshots (gowitness) | — | — | ✓ |
| HTML dark-mode report + JSON output | ✓ | ✓ | ✓ |

### Other highlights

- **Resume** — each phase checks its output file and skips if already complete; use `--force` to re-run everything
- **Colored output** — green `[+]` info, yellow `[!]` warnings, red `[x]` errors, each with a timestamp
- **Progress counter** — `[x/N]` during DNS resolution when bulk tools are unavailable
- **Configurable rate limits** — `--rl-httpx`, `--rl-katana`, `--rl-nuclei`
- **External wordlist** — `-w /path/to/list` for DNS brute-force with a built-in 30-word fallback
- **Dynamic banner** — adapts to any terminal width, no fixed-width box

---

## Install (Kali)

### APT dependencies
```bash
chmod +x install.sh
sudo ./install.sh
```

### Recommended tools (ProjectDiscovery / Go)
Install via official releases or `go install`:

```
subfinder    httpx    katana    nuclei    dnsx    amass
gau          gowitness
```

### Optional system tools
```
whois    wafw00f    whatweb    testssl.sh
```

All tools are optional — phases are skipped with a warning if a tool is missing.

---

## Usage

```bash
chmod +x recon-ultra.sh

# Quick passive OSINT
./recon-ultra.sh -t example.com --passive

# Default (low-noise enumeration + HTTP + wayback)
./recon-ultra.sh -t example.com --light

# Full pipeline
./recon-ultra.sh -t example.com --active

# Custom output dir, no DNS brute, silent banner
./recon-ultra.sh -t example.com --active -o /tmp/out --no-brute --quiet

# External wordlist for brute-force
./recon-ultra.sh -t example.com --active -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt

# Tune rate limits
./recon-ultra.sh -t example.com --active --rl-httpx 30 --rl-nuclei 5

# Re-run skipping nothing (overwrite cached output)
./recon-ultra.sh -t example.com --active --force
```

### All flags

| Flag | Default | Description |
|------|---------|-------------|
| `-t`, `--target` | — | Target domain *(required)* |
| `-o`, `--out` | `./out/<target>` | Output directory |
| `--passive` | — | Passive OSINT only |
| `--light` | ✓ | Low-noise enumeration (default) |
| `--active` | — | Full pipeline |
| `--no-brute` | — | Disable DNS brute-force |
| `-w`, `--wordlist` | built-in | External wordlist for brute-force |
| `--rl-httpx N` | `50` | httpx requests/s |
| `--rl-katana N` | `10` | katana requests/s |
| `--rl-nuclei N` | `10` | nuclei requests/s |
| `--force` | — | Overwrite cached output (disable resume) |
| `--quiet`, `-q` | — | Suppress banner |
| `-h`, `--help` | — | Show help |

---

## Output structure

```
out/<target>/
├── subdomains/
│   ├── subdomains_all.txt          # merged & deduplicated
│   ├── subdomains_bruteforce.txt   # dnsx brute results
│   └── words_builtin.txt           # wordlist used (if no -w)
├── dns/
│   ├── A.txt                       # hostname → IPv4
│   ├── AAAA.txt                    # hostname → IPv6
│   ├── CNAME.txt                   # CNAME chains
│   ├── MX.txt                      # mail exchangers
│   ├── NS.txt                      # nameservers
│   └── TXT.txt                     # SPF / DMARC / DKIM / misc
├── http/
│   ├── hosts.txt                   # input list for httpx
│   └── alive.txt                   # live hosts with title, tech, status
├── scan/
│   ├── whois.txt                   # WHOIS raw output
│   ├── wayback.txt                 # historical URLs
│   ├── crawl.txt                   # katana crawl results
│   ├── nuclei.txt                  # vulnerability findings
│   ├── waf.txt                     # WAF detection (active only)
│   ├── whatweb.txt                 # tech fingerprint (active only)
│   ├── tls.txt                     # TLS audit (active only)
│   └── screenshots/                # gowitness PNGs (active only)
└── report/
    ├── report.html                 # dark-mode HTML report with stats
    └── report.json                 # structured JSON summary
```

---

## Legal

Use **ONLY** on assets you own or where you have **explicit written authorization**.

*Memento Mori — by The IT Bear*

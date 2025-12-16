# Recon ULTRA 

A **Kali-friendly**, bash-first recon pipeline that blends **OSINT + passive subdomain discovery + light active checks**
with a clean folder structure and a single HTML report.

> ⚠️ Use only on targets you **own** or where you have **explicit written authorization**.

## Features

- Passive OSINT: WHOIS + Certificate Transparency (crt.sh)
- Subdomain enumeration: `subfinder`, `amass` (passive), optional `dnsx` brute
- DNS resolution with A/AAAA/CNAME capture
- Optional fingerprinting: WAF/CDN (`wafw00f`), tech (`whatweb`), headers
- Optional crawling: `katana` (depth 2 by default)
- Optional light scanning: `nuclei` (rate-limited), optional `testssl.sh`
- HTML report generation (safe HTML escaping)

## Install (Kali)

```bash
sudo apt update
sudo apt install -y jq whois
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/owasp-amass/amass/v4/...@latest
go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
sudo apt install -y wafw00f whatweb
# optional
sudo apt install -y testssl.sh
```

Make it executable:

```bash
chmod +x ./recon-ultra.sh
```

## Usage

### Passive only (quiet)
```bash
./recon-ultra.sh -d example.com --passive
```

### Light (adds fingerprinting + crawling)
```bash
./recon-ultra.sh -d example.com --light
```

### Active (adds nuclei + optional TLS checks)
```bash
./recon-ultra.sh -d example.com --active
```

### Useful flags
```bash
./recon-ultra.sh -d example.com -o out-example -t 20 --no-brute --no-report
```

## Output

A run creates:

- `out-*/subdomains/` (raw + normalized)
- `out-*/dns/` (resolved A/AAAA/CNAME, unresolved)
- `out-*/http/` (alive hosts, headers, whatweb, waf)
- `out-*/crawl/` (katana output)
- `out-*/scan/` (nuclei, testssl)
- `out-*/report.html`

## License
MIT – see `LICENSE`.

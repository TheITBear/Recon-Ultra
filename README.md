# Recon-Ultra 

**RECON ULTRA** is a Kali Linux–focused reconnaissance wrapper that combines passive OSINT and controlled active enumeration into clean, actionable outputs and a safe HTML report.

> **Kali-only by design.** Other distros are intentionally out of scope to keep dependencies predictable.

## Features

- Modes: `--passive` / `--light` / `--active`
- Subdomain enumeration (subfinder, amass passive, crt.sh)
- DNS resolution (A / AAAA / CNAME)
- Live host discovery (httpx)
- Fingerprinting (whatweb) *(optional)*
- Crawling (katana) *(optional)*
- Light scanning (nuclei) *(optional)*
- HTML report generation with output escaping

## Install (Kali)

### APT dependencies
```bash
chmod +x install.sh
sudo ./install.sh
```

### Recommended (ProjectDiscovery / Go tools)
Install via official releases or `go install`:
- `subfinder`
- `httpx`
- `katana`
- `nuclei`
- `dnsx`
- `amass` (optional)

## Usage

```bash
chmod +x recon-ultra.sh

./recon-ultra.sh -t example.com --light
./recon-ultra.sh -t example.com --active
./recon-ultra.sh -t example.com --passive -o out/example
./recon-ultra.sh -t example.com --active --no-brute
./recon-ultra.sh -t example.com --active --quiet
```

## Output

Outputs are written under `out/<target>/` by default:
- `subdomains/*.txt`
- `dns/*.txt`
- `http/*.txt`
- `scan/*.txt`
- `report/report.html`

## Legal

Use **ONLY** on assets you own or where you have **explicit authorization**.

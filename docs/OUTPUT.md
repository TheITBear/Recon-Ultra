# Output layout

The tool writes everything under the chosen output directory:

- `osint/`
  - `whois.txt`
  - `crt.txt`
  - `reverse_ip.txt` (best-effort)
- `subdomains/`
  - `subs_raw.txt`
  - `subdomains.txt`
- `dns/`
  - `a.txt`, `aaaa.txt`, `cname.txt`, `unresolved.txt`
- `http/`
  - `alive.txt`, `headers.txt`, `whatweb.txt`, `waf.txt`
- `crawl/`
  - `crawl.txt`
- `scan/`
  - `nuclei.txt`, `ssl.txt`
- `report.html`

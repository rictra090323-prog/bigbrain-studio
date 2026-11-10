"""Fetch public HTML with explicit redirect checks and DNS pinning."""
import ipaddress
from pathlib import Path
import re
import socket
import subprocess
import tempfile
from urllib.parse import urlsplit

MAX_BYTES = 2_000_000


def public_target(value):
    if any(ord(c) < 33 or ord(c) == 127 for c in value) or "\\" in value:
        raise ValueError("Källänken innehåller ogiltiga tecken.")
    url = urlsplit(value)
    if url.scheme not in ("http", "https") or not url.hostname or url.username is not None:
        raise ValueError("Ange en offentlig http- eller https-länk.")
    port = 443 if url.scheme == "https" else 80
    if url.port not in (None, port):
        raise ValueError("Källhämtning använder webbens standardportar.")
    host = url.hostname.encode("idna").decode("ascii")
    if "%" in host or host.endswith("."):
        raise ValueError("Källänken innehåller ett ogiltigt värdnamn.")
    try:
        resolved = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError as error:
        raise ValueError("Källans domän kunde inte slås upp.") from error
    addresses = {ipaddress.ip_address(item[4][0]) for item in resolved}
    for original in addresses:
        ip = (getattr(original, "ipv4_mapped", None) or original)
        if not ip.is_global or ip.is_multicast or getattr(ip, "is_site_local", False):
            raise ValueError("Källhämtning är begränsad till offentliga internetadresser.")
    if not addresses:
        raise ValueError("Källans domän saknar en offentlig adress.")
    ip = sorted(addresses, key=lambda value: (value.version, int(value)))[0]
    return url, host, port, ip


def fetch(source):
    with tempfile.TemporaryDirectory(prefix="bigbrain-source-") as directory:
        destination = Path(directory) / "source.html"
        for _ in range(5):
            url, host, port, ip = public_target(source)
            literal = f"[{ip}]" if ip.version == 6 else str(ip)
            # A numeric URL already pins its address. Named hosts keep TLS SNI and certificate validation.
            resolve = [] if ":" in host else ["--resolve", f"{host}:{port}:{literal}"]
            authority = f"[{host}]" if ":" in host else host
            source = url._replace(netloc=authority, fragment="").geturl()
            result = subprocess.run(
                ["/usr/bin/curl", "-q", "--silent", "--show-error", "--noproxy", "*",
                 "--proto", "=http,https", "--connect-timeout", "7", "--max-time", "12",
                 "--max-filesize", str(MAX_BYTES), "--user-agent", "BigBrain/2 (article reader)",
                 *resolve, "--output", str(destination),
                 "--write-out", "%{response_code}\n%{redirect_url}\n%{content_type}", "--url", source],
                capture_output=True, text=True, timeout=15, check=True)
            status, redirect, content_type = result.stdout.split("\n", 2)
            if status in {"301", "302", "303", "307", "308"} and redirect:
                source = redirect
                continue
            if status != "200" or "html" not in content_type.lower():
                raise ValueError("Källan gav ingen läsbar HTML-sida.")
            html = destination.read_bytes()
            if len(html) > MAX_BYTES:
                raise ValueError("Källsidan är för stor.")
            charset = re.search(r"charset\s*=\s*['\"]?([\w-]+)", content_type, re.I)
            try:
                return html.decode(charset[1] if charset else "utf-8", errors="replace")
            except LookupError:
                return html.decode("utf-8", errors="replace")
    raise ValueError("Källänken gjorde för många omdirigeringar.")

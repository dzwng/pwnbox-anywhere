"""Validate a private Serve HTTP entry point without replacing existing routes."""
import ipaddress
import re
from urllib.parse import urlsplit

TCP_TARGET = "127.0.0.1:8788"


def plan(node, serve, public_url):
    if not isinstance(serve, dict):
        raise ValueError("Unrecognized Tailscale Serve configuration.")
    configs = [serve, *serve.get("Foreground", {}).values()]
    if any(any(config.get("AllowFunnel", {}).values()) for config in configs):
        raise ValueError("Funnel is configured; review it before adding a private shortcut.")
    name = node.get("Self", {}).get("DNSName", "").rstrip(".").lower()
    if not re.fullmatch(r"[a-z0-9-]+(?:\.[a-z0-9-]+)+\.ts\.net", name):
        raise ValueError("A Tailscale MagicDNS name is required.")
    url = urlsplit(public_url)
    if url.scheme != "https" or url.hostname != name or url.path not in ("", "/") or url.query or url.fragment or url.username:
        raise ValueError("The dashboard URL must match this ThinkPad's HTTPS Tailscale name.")
    https_port = str(url.port or 443)
    https_route = serve.get("Web", {}).get(name + ":" + https_port, {}).get("Handlers", {}).get("/")
    if https_route != {"Proxy": "http://127.0.0.1:8787"} or not serve.get("TCP", {}).get(https_port, {}).get("HTTPS"):
        raise ValueError("The dashboard's existing HTTPS Serve route could not be verified.")
    # Existing TCP or HTTP services on port 80 belong to their owner.
    web80 = {key: value for key, value in serve.get("Web", {}).items() if key.endswith(":80")}
    tcp80 = serve.get("TCP", {}).get("80")
    already = tcp80 == {"TCPForward": TCP_TARGET} and not web80
    for config in configs[1:]:
        if "80" in config.get("TCP", {}) or any(key.endswith(":80") for key in config.get("Web", {})):
            raise ValueError("Tailscale port 80 already serves a foreground service; its routes were preserved.")
    if (tcp80 is not None or web80) and not already:
        raise ValueError("Tailscale port 80 already serves another service; its routes were preserved.")
    addresses = []
    for raw in node.get("Self", {}).get("TailscaleIPs", []):
        try:
            address = ipaddress.ip_address(raw)
        except ValueError:
            continue
        if address.version == 4 and address in ipaddress.ip_network("100.64.0.0/10"):
            addresses.append("http://" + str(address) + ":80")
    if not addresses:
        raise ValueError("The ThinkPad needs a Tailscale IPv4 address.")
    return {"already": already, "urls": ["http://" + name.split(".")[0]] + addresses}

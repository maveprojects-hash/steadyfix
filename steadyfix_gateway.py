#!/usr/bin/env python3
"""
STEADYFIX computer gateway (PRO plan).

Run it on any PC or Raspberry Pi that stays switched on inside the building. It finds the devices on
your network by itself, reports them to the STEADYFIX app every couple of minutes, and updates itself.
Needs Python 3 only. Nothing else to install.

First run:   python3 steadyfix_gateway.py      (it asks for your site key once and remembers it)
Just look:   python3 steadyfix_gateway.py scan (lists devices without reporting)
"""
import os, re, sys, json, time, socket, subprocess, platform, ipaddress, urllib.request
from concurrent.futures import ThreadPoolExecutor

VERSION = "2.0"
SUPABASE_URL = "https://wqggnimaglsikdusbvuh.supabase.co"
PUBLISHABLE_KEY = "sb_publishable_NhiAgVZ451DMdfwzWTSGvQ_zQlbwW8l"
UPDATE_URL = "https://maveprojects-hash.github.io/steadyfix/steadyfix_gateway.py"
INTERVAL = 120  # seconds between scans
HERE = os.path.dirname(os.path.abspath(__file__))
KEYFILE = os.path.join(HERE, "steadyfix_key.txt")
WIN = platform.system().lower() == "windows"


def ping(host):
    cmd = ["ping", "-n", "1", "-w", "1500", host] if WIN else ["ping", "-c", "1", "-W", "2", host]
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    except OSError:
        return False


def local_network():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
    except OSError:
        ip = "192.168.1.10"
    finally:
        s.close()
    return ipaddress.ip_network(ip + "/24", strict=False)


def parse_arp(text):
    return {m.group(1): m.group(2).lower().replace("-", ":") for m in re.finditer(
        r"(\d+\.\d+\.\d+\.\d+).*?([0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5})", text)}


def scan():
    hosts = [str(h) for h in local_network().hosts()]
    with ThreadPoolExecutor(64) as ex:
        alive = [h for h, ok in zip(hosts, ex.map(ping, hosts)) if ok]
    try:
        macs = parse_arp(subprocess.run(["arp", "-a"], capture_output=True, text=True).stdout)
    except OSError:
        macs = {}
    out = []
    for ip in alive:
        try:
            name = socket.gethostbyaddr(ip)[0].split(".")[0]
        except OSError:
            name = ""
        out.append({"ip": ip, "mac": macs.get(ip, ""), "name": name or ip, "up": True})
    return out


def call(key, devices):
    req = urllib.request.Request(
        SUPABASE_URL + "/rest/v1/rpc/agent_sync",
        data=json.dumps({"p_agent_key": key, "p_devices": devices}).encode(),
        headers={"apikey": PUBLISHABLE_KEY, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode()).get("message", "")
        except Exception:
            msg = ""
        print("   The app said:", msg or e)
    except Exception as e:
        print("   Could not reach the app:", e)
    return None


def self_update(latest):
    if not latest or latest == VERSION:
        return
    try:
        text = urllib.request.urlopen(UPDATE_URL, timeout=20).read().decode()
        m = re.search(r'^VERSION = "([^"]+)"', text, re.M)
        if m and m.group(1) != VERSION and "def scan" in text:
            with open(os.path.abspath(__file__), "w", encoding="utf-8") as f:
                f.write(text)
            print("Updated to version", m.group(1), "- restarting")
            os.execv(sys.executable, [sys.executable] + sys.argv)
    except Exception as e:
        print("   Update check failed:", e)


def get_key():
    if os.path.exists(KEYFILE):
        return open(KEYFILE).read().strip()
    key = input("Paste your site key from the app (Monitoring > Computer gateway): ").strip()
    with open(KEYFILE, "w") as f:
        f.write(key)
    return key


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "scan":
        for d in scan():
            print(f"{d['ip']:<16} {d['mac']:<19} {d['name']}")
        return
    key = get_key()
    print(f"STEADYFIX gateway {VERSION} running. Press Ctrl+C to stop.")
    while True:
        devices = scan()
        res = call(key, devices)
        stamp = time.strftime("%H:%M:%S")
        if res:
            print(f"{stamp} {len(devices)} devices found, {res.get('created', 0)} new, {res.get('skipped', 0)} skipped (plan limit)")
            self_update(res.get("latest_version"))
        else:
            print(f"{stamp} {len(devices)} devices found but not reported")
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()

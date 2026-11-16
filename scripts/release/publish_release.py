"""通过固定 IP + OpenSSL 调 GitHub API：创建 Release 并上传附件。

背景：本机网络 HTTPS 到 github.com/api.github.com 被按域名阻断（curl 的 Schannel 与系统 DNS
都走不通），但直连 GitHub 各边缘 IP 的 443 是通的。这里把 api.github.com / uploads.github.com
固定到实测可用 IP，走 Python 自带的 OpenSSL 栈，实现免代理发布。

用法：
  python scripts/release/publish_release.py <tag> <title> <notes-file> <asset> [<asset> ...]
"""
import json
import socket
import ssl
import sys
import urllib.request
from pathlib import Path

API_IP = "140.82.112.6"      # api.github.com（实测可用）
UPLOAD_IP = "140.82.112.9"   # uploads.github.com（实测可用）
REPO = "zhumin2/discord-like"
TOKEN = __import__("os").environ.get("GH_TOKEN", "")

if not TOKEN:
    raise SystemExit("请设置环境变量 GH_TOKEN")

_real_getaddrinfo = socket.getaddrinfo


def _patch():
    def patched(host, *a, **k):
        if host == "api.github.com":
            host = API_IP
        elif host == "uploads.github.com":
            host = UPLOAD_IP
        return _real_getaddrinfo(host, *a, **k)
    socket.getaddrinfo = patched


def api(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        "https://api.github.com" + path, data=data, method=method,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Accept": "application/vnd.github+json",
            "User-Agent": "chord-release",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def upload(upload_url_template: str, file: Path) -> dict:
    """POST 二进制到 uploads.github.com（Content-Type: octet-stream）。"""
    asset_url = upload_url_template.split("{")[0] + "?name=" + file.name
    host_path = asset_url.split("uploads.github.com", 1)[1]
    ctx = ssl.create_default_context()
    conn = __import__("http.client", fromlist=["HTTPSConnection"]).HTTPSConnection(
        "uploads.github.com", 443, context=ctx, timeout=600
    )
    size = file.stat().st_size
    conn.putrequest("POST", host_path)
    conn.putheader("Authorization", "Bearer " + TOKEN)
    conn.putheader("Accept", "application/vnd.github+json")
    conn.putheader("User-Agent", "chord-release")
    conn.putheader("Content-Type", "application/octet-stream")
    conn.putheader("Content-Length", str(size))
    conn.endheaders()
    with file.open("rb") as f:
        while True:
            chunk = f.read(1024 * 256)
            if not chunk:
                break
            conn.send(chunk)
    resp = conn.getresponse()
    raw = resp.read()
    conn.close()
    if resp.status >= 300:
        raise SystemExit(f"上传 {file.name} 失败: {resp.status} {raw[:300]!r}")
    return json.loads(raw)


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    tag, title, notes_file = sys.argv[1], sys.argv[2], sys.argv[3]
    assets = [Path(p) for p in sys.argv[4:]]

    _patch()
    me = api("GET", "/user")
    print("身份:", me["login"])

    # 已存在则复用（幂等）
    try:
        rel = api("GET", f"/repos/{REPO}/releases/tags/{tag}")
        print("Release 已存在，复用:", rel["html_url"])
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        rel = api("POST", f"/repos/{REPO}/releases", {
            "tag_name": tag,
            "name": title,
            "body": Path(notes_file).read_text(encoding="utf-8"),
            "draft": False,
            "prerelease": False,
            "target_commitish": "main",
        })
        print("Release 已创建:", rel["html_url"])

    existing = {a["name"]: a for a in api("GET", f"/repos/{REPO}/releases/{rel['id']}/assets")}
    upload_url = rel["upload_url"]
    for f in assets:
        if not f.exists():
            raise SystemExit(f"附件不存在: {f}")
        if f.name in existing:
            api("DELETE", f"/repos/{REPO}/releases/assets/{existing[f.name]['id']}")
            print("已删除旧附件:", f.name)
        info = upload(upload_url, f)
        print(f"上传成功: {f.name}  {info['size']/1048576:.1f}MB  digest={info.get('digest','-')[:20]}")

    print("完成:", rel["html_url"])
    return 0


if __name__ == "__main__":
    sys.exit(main())

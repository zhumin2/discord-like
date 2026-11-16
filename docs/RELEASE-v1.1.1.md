## v1.1.1 — Web 打开速度专项修复

线上 Web 版"好难打开"的两个根因已定位并修复。

### 主要变化

| 修复 | 说明 | 效果 |
|---|---|---|
| CanvasKit 本地化 | 之前从 `www.gstatic.com` 加载（国内被墙，请求挂起 → 白屏/卡死），改为随站点自托管 | 不再卡 CDN，引擎 1 秒内就绪 |
| 中文字体子集化 | 全量 NotoSansSC 两字重共 20MB，子集化为 GB2312 常用 7562 字 | 字体 20MB → 4.6MB（覆盖约 99.7%） |
| 内容哈希 + 长缓存 | 产物文件名带内容哈希，静态服务器对哈希资源发 `immutable` 一年 | **二次访问零下载** |

首屏资源：**28.5MB → 13MB**（gzip 后约 5MB）。

### 升级方式（服务器上执行）

```bash
# 1. 先刷新更新脚本（新脚本支持同时升级静态服务器）
sudo curl -fLo /opt/chord/update.sh \
  https://github.com/zhumin2/discord-like/releases/latest/download/update.sh

# 2. 执行 Web 更新
sudo bash /opt/chord/update.sh web
```

然后浏览器 **Ctrl+F5** 强制刷新一次（清除旧缓存），之后即可享受秒开与稳定缓存。

### 备注

- 若你的网络管理器缓存了旧 bundle，请务必强刷；如仍然异常可清站点数据。
- 生僻字（GB2312 之外）会显示为方框；如需完整字符集，可在仓库执行
  `python scripts/fonts/subset_fonts.py --restore` 后重新构建。
- 首次加载仍需下载约 5MB（跨境带宽限制），后续访问几乎零流量。

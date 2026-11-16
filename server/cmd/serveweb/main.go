// 静态文件服务器：为 Flutter Web 构建产物（client/build/web）提供托管。
// 用法: serveweb -dir ../client/build/web -port 3000
//
// v1.1 新增：gzip 压缩（首屏传输 10MB→约2.5MB）+ 指纹资源长缓存。
package main

import (
	"compress/gzip"
	"flag"
	"log"
	"net/http"
	"path/filepath"
	"regexp"
	"strings"
)

// compressible 判断响应类型是否值得压缩（文本类 + wasm：canvaskit.wasm 压缩比约 2.8 倍）。
func compressible(ct string) bool {
	return strings.HasPrefix(ct, "text/") ||
		ct == "application/javascript" ||
		ct == "application/json" ||
		ct == "image/svg+xml" ||
		ct == "application/wasm"
}

// contentTypeFor 按扩展名给出 Content-Type；binary 表示不压缩、交给 FileServer 自行判断。
func contentTypeFor(p string) string {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".html", ".htm":
		return "text/html; charset=utf-8"
	case ".js", ".mjs":
		return "application/javascript"
	case ".css":
		return "text/css"
	case ".json":
		return "application/json"
	case ".svg":
		return "image/svg+xml"
	case ".wasm":
		return "application/wasm"
	}
	return ""
}

// ---- 缓存策略 ----

// hashedAssetRe 匹配带内容哈希的文件名（如 main.dart.cc12c555.js、NotoSansSC-Bold.b55fb621.ttf）。
// 由前端 `flutter build web --web-content-hash` 生成：内容变化时文件名随之变化，
// 因此可以安全长缓存（immutable）；升级后新 index/bootstrap 指向新文件名，旧文件自然淘汰。
var hashedAssetRe = regexp.MustCompile(`\.[0-9a-f]{8,}\.[A-Za-z0-9]+$`)

// cacheControl 按路径返回 Cache-Control。
//   - 入口/清单：no-cache（每次协商，304 很便宜，且有 gzip）——保证升级立即生效
//   - 带内容哈希的资源：1 年 immutable（二次访问零请求）
//   - 未哈希的资源（canvaskit/**、icons/** 在 --no-web-resources-cdn 下不做哈希）：1 小时
//
// 注意：绝不能给**未哈希**的稳定文件名（canvaskit.wasm、旧版 main.dart.js）设长缓存——
// v1.1 曾因 immutable 导致升级后继续用旧 bundle/旧图标字体（按钮空白）。
func cacheControl(p string) string {
	switch p {
	case "/", "/index.html", "/flutter_bootstrap.js", "/flutter_service_worker.js",
		"/flutter.js", "/version.json", "/manifest.json", "/precache_manifest.json", "/favicon.png":
		return "no-cache"
	}
	if hashedAssetRe.MatchString(p) {
		return "public, max-age=31536000, immutable"
	}
	if strings.HasPrefix(p, "/assets/") ||
		strings.HasPrefix(p, "/canvaskit/") ||
		strings.HasPrefix(p, "/icons/") {
		return "public, max-age=3600"
	}
	return ""
}

// ---- gzip 响应包装 ----

// gzipResponseWriter 拦截 WriteHeader 删除未压缩的 Content-Length，
// 避免 http.ServeContent 预设长度与 gzip 实际输出不一致导致截断；
// 并声明 Content-Encoding（仅对有实体的响应——304 等无 body 状态不声明）。
type gzipResponseWriter struct {
	http.ResponseWriter
	gz      *gzip.Writer
	started bool
}

func (w *gzipResponseWriter) WriteHeader(code int) {
	if w.started {
		return
	}
	w.started = true
	w.Header().Del("Content-Length")
	w.Header().Add("Vary", "Accept-Encoding")
	if code == http.StatusOK || code == http.StatusPartialContent {
		w.Header().Set("Content-Encoding", "gzip")
	}
	w.ResponseWriter.WriteHeader(code)
}

func (w *gzipResponseWriter) Write(b []byte) (int, error) {
	if !w.started {
		w.WriteHeader(http.StatusOK)
	}
	return w.gz.Write(b)
}

func main() {
	dir := flag.String("dir", "../client/build/web", "静态目录")
	port := flag.String("port", "3000", "监听端口")
	flag.Parse()

	abs, _ := filepath.Abs(*dir)
	mux := http.NewServeMux()
	fs := http.FileServer(http.Dir(abs))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// CORS 允许跨源调试（同源部署时可去掉）
		w.Header().Set("Access-Control-Allow-Origin", "*")

		p := r.URL.Path
		// 缓存策略（必须在 WriteHeader 之前）
		if cc := cacheControl(p); cc != "" {
			w.Header().Set("Cache-Control", cc)
		}

		// Flutter Web 路由回退到 index.html
		if p != "/" && !strings.Contains(filepath.Ext(p), ".") {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Cache-Control", "no-cache")
			http.ServeFile(w, r, filepath.Join(abs, "index.html"))
			return
		}

		// 关键 MIME：显式设置（gzip 分支也依赖它）
		ct := contentTypeFor(p)
		if strings.HasSuffix(p, ".wasm") {
			w.Header().Set("Content-Type", "application/wasm")
		} else if ct != "" {
			w.Header().Set("Content-Type", ct)
		}

		// gzip：可压缩类型 + 客户端接受 + 非 HEAD
		if ct != "" && compressible(ct) &&
			r.Method != http.MethodHead &&
			strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") {
			gz := gzip.NewWriter(w)
			defer gz.Close()
			fs.ServeHTTP(&gzipResponseWriter{ResponseWriter: w, gz: gz}, r)
			return
		}
		fs.ServeHTTP(w, r)
	})

	log.Printf("[serve-web] serving %s on http://0.0.0.0:%s (gzip=on)", abs, *port)
	log.Fatal(http.ListenAndServe(":"+*port, mux))
}

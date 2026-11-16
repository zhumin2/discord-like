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

// cacheControl 按路径返回 Cache-Control。
// 注意：Flutter Web 构建产物的文件名**不含内容哈希**（main.dart.js、字体、canvaskit 都是稳定名），
// 因此绝不能长缓存——否则升级后浏览器继续用旧 bundle/旧图标字体（v1.1 曾因此丢图标与旧代码）。
//   - 入口与 bundle：no-cache（每次协商，304 很便宜，且有 gzip）
//   - 其余资源：1 小时（同一构建内可复用，升级后最多 1 小时自然过期）
func cacheControl(p string) string {
	switch p {
	case "/", "/index.html", "/flutter_bootstrap.js", "/flutter_service_worker.js",
		"/main.dart.js", "/flutter.js", "/version.json", "/manifest.json", "/favicon.png":
		return "no-cache"
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

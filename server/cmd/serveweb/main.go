// 静态文件服务器：为 Flutter Web 构建产物（client/build/web）提供托管。
// 用法: go run ./cmd/serveweb -dir ../client/build/web -port 3000
package main

import (
	"flag"
	"log"
	"net/http"
	"path/filepath"
	"strings"
)

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
		// Flutter Web 路由回退到 index.html
		p := r.URL.Path
		if p != "/" && !strings.Contains(filepath.Ext(p), ".") {
			http.ServeFile(w, r, filepath.Join(abs, "index.html"))
			return
		}
		// 关键 MIME：CanvasKit/Skwasm 的 wasm
		if strings.HasSuffix(p, ".wasm") {
			w.Header().Set("Content-Type", "application/wasm")
		}
		fs.ServeHTTP(w, r)
	})

	log.Printf("[serve-web] serving %s on http://0.0.0.0:%s", abs, *port)
	log.Fatal(http.ListenAndServe(":"+*port, mux))
}

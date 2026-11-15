package handlers

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"chord/server/internal/config"
)

// newUploadServer 构造仅用于上传链路的 Server（不依赖 DB/Hub）。
func newUploadServer(t *testing.T) (*Server, string) {
	t.Helper()
	dir := t.TempDir()
	gin.SetMode(gin.TestMode)
	return &Server{Cfg: &config.Config{UploadDir: dir, JWTSecret: "test-secret"}}, dir
}

// closeNotifyingRecorder 补齐 gin.ResponseWriter 要求的 CloseNotify。
type closeNotifyingRecorder struct {
	*httptest.ResponseRecorder
}

func (c *closeNotifyingRecorder) CloseNotify() <-chan bool { return make(chan bool) }

func (c *closeNotifyingRecorder) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	return nil, nil, errors.New("not supported in tests")
}

func (c *closeNotifyingRecorder) Pusher() http.Pusher { return nil }

func (c *closeNotifyingRecorder) Size() int { return c.Body.Len() }

func (c *closeNotifyingRecorder) Status() int { return c.Code }

func (c *closeNotifyingRecorder) Written() bool { return c.Body.Len() > 0 }

func (c *closeNotifyingRecorder) WriteHeaderNow() {}

func (c *closeNotifyingRecorder) Flush() {}

// uploadRequest 构造一次 multipart 上传请求并执行 Upload 处理器。
func uploadRequest(t *testing.T, s *Server, filename string, content []byte) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	fw, _ := w.CreateFormFile("file", filename)
	fw.Write(content)
	w.Close()

	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = httptest.NewRequest("POST", "/api/upload", &buf)
	c.Request.Header.Set("Content-Type", w.FormDataContentType())
	c.Writer = &closeNotifyingRecorder{rec}
	s.Upload(c)
	return rec
}

func TestUploadAcceptsAllowedExt(t *testing.T) {
	s, dir := newUploadServer(t)
	rec := uploadRequest(t, s, "hello.png", []byte("fakepng"))
	if rec.Code != 200 {
		t.Fatalf("png 上传应成功，得到 %d：%s", rec.Code, rec.Body.String())
	}
	var resp struct{ URL string `json:"url"` }
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil || resp.URL == "" {
		t.Fatalf("返回应含 url 字段：%s", rec.Body.String())
	}
	if !strings.HasPrefix(resp.URL, "/uploads/") {
		t.Fatalf("url 应以 /uploads/ 开头：%s", resp.URL)
	}
	// 文件确实落盘且内容一致
	var found bool
	filepath.Walk(dir, func(p string, _ os.FileInfo, _ error) error {
		if strings.HasSuffix(p, ".png") {
			found = true
			data, _ := os.ReadFile(p)
			if !bytes.Equal(data, []byte("fakepng")) {
				t.Fatal("落盘内容与上传不一致")
			}
		}
		return nil
	})
	if !found {
		t.Fatal("文件未落盘")
	}
}

func TestUploadRejectsBadExt(t *testing.T) {
	s, _ := newUploadServer(t)
	rec := uploadRequest(t, s, "evil.exe", []byte("MZ..."))
	if rec.Code != 415 {
		t.Fatalf("exe 上传应 415，得到 %d", rec.Code)
	}
}

func TestUploadRejectsOversize(t *testing.T) {
	s, _ := newUploadServer(t)
	rec := uploadRequest(t, s, "big.png", bytes.Repeat([]byte("a"), 10<<20+1))
	if rec.Code != 413 {
		t.Fatalf("超限上传应 413，得到 %d", rec.Code)
	}
}

func TestServeUploadBlocksTraversal(t *testing.T) {
	s, dir := newUploadServer(t)
	os.WriteFile(filepath.Join(dir, "secret.txt"), []byte("top-secret"), 0o644)

	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = httptest.NewRequest("GET", "/uploads/../secret.txt", nil)
	c.Params = gin.Params{{Key: "filepath", Value: "/../secret.txt"}}
	c.Request.URL.Path = "/uploads/../secret.txt"
	c.Writer = &closeNotifyingRecorder{rec}
	s.serveUpload(c)

	if rec.Code == 200 && strings.Contains(rec.Body.String(), "top-secret") {
		t.Fatal("路径穿越攻击成功——serveUpload 防护失效！")
	}
}

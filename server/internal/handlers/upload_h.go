package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"io"
	"mime"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// ---- v1.1 文件/图片上传 ----

// maxUpload 10MB（与 ROADMAP B1 一致）。
const maxUpload = 10 << 20

// extAllowlist 上传白名单：图片 + 常用文档/媒体。
var extAllowlist = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
	".svg": true, ".txt": true, ".pdf": true, ".zip": true,
	".mp3": true, ".mp4": true, ".mov": true, ".webm": true,
	".doc": true, ".docx": true, ".xls": true, ".xlsx": true, ".ppt": true, ".pptx": true,
}

// Upload 处理 multipart 上传，落盘 {UPLOAD_DIR}/yyyyMM/<uuid><ext>。
// 返回相对 URL（/uploads/...），前端以 Markdown 语法写进消息内容。
func (s *Server) Upload(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		fail(c, 400, "缺少 file 字段（multipart）")
		return
	}
	if file.Size > maxUpload {
		fail(c, 413, "文件超过 10MB 限制")
		return
	}
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if !extAllowlist[ext] {
		fail(c, 415, "不支持的文件类型: "+ext)
		return
	}

	// 目录：yyyyMM/uuid.ext（随机名防猜测、防穿越）
	now := time.Now()
	sub := now.Format("200601")
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		fail(c, 500, "生成文件名失败")
		return
	}
	name := hex.EncodeToString(buf) + ext
	dir := filepath.Join(s.Cfg.UploadDir, sub)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		fail(c, 500, "创建目录失败")
		return
	}
	dst := filepath.Join(dir, name)

	src, err := file.Open()
	if err != nil {
		fail(c, 400, "读取上传内容失败")
		return
	}
	defer src.Close()
	out, err := os.Create(dst)
	if err != nil {
		fail(c, 500, "写入文件失败")
		return
	}
	defer out.Close()
	if _, err := io.Copy(out, io.LimitReader(src, maxUpload+1)); err != nil {
		fail(c, 500, "保存文件失败")
		return
	}
	// 兜底：万一写入超限（LimitReader 已裁剪，正常不会触发）
	if fi, _ := out.Stat(); fi != nil && fi.Size() > maxUpload {
		_ = os.Remove(dst)
		fail(c, 413, "文件超过 10MB 限制")
		return
	}

	c.JSON(200, gin.H{
		"url":  "/uploads/" + sub + "/" + name,
		"name": file.Filename,
		"size": file.Size,
	})
}

// serveUpload 公开读取上传文件：文件名是不可猜测的 UUID，链接随消息自然共享。
func (s *Server) serveUpload(c *gin.Context) {
	rel := c.Param("filepath")
	// 防穿越：拒绝任何 .. 与绝对路径成分
	if strings.Contains(rel, "..") || strings.HasPrefix(rel, "/") && filepath.IsAbs(rel) {
		fail(c, 400, "非法路径")
		return
	}
	full := filepath.Join(s.Cfg.UploadDir, filepath.FromSlash(rel))
	fi, err := os.Stat(full)
	if err != nil || fi.IsDir() {
		fail(c, 404, "文件不存在")
		return
	}
	// 文件名不可变 → 长缓存
	c.Header("Cache-Control", "public, max-age=31536000, immutable")
	ext := strings.ToLower(filepath.Ext(full))
	if ct := mime.TypeByExtension(ext); ct != "" {
		c.Header("Content-Type", ct)
	}
	c.File(full)
}

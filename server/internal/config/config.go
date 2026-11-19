package config

import (
	"os"
	"path/filepath"
	"strconv"

	"github.com/joho/godotenv"

	"chord/server/internal/util"
)

type Config struct {
	Port          string
	DBDSN         string
	RedisAddr     string // 为空则使用进程内实现（单实例开发模式）
	JWTSecret     string
	SeedDemo      bool
	ClientOrigins []string // 允许的 CORS 来源，空则允许全部（开发模式）
	UploadDir     string   // 上传文件根目录（v1.1）
	SendIntervalMS int     // 同一用户两条消息的最小间隔毫秒（0=不限），防 AI 灌水
}

// Load 读取 .env（若存在）与环境变量。DSN/Secret 提供开发期默认值，
// 使 `go run ./cmd/server` 在全新机器上也能直接启动。
func Load() *Config {
	_ = godotenv.Load() // 忽略错误：.env 可选
	// 同时尝试 server/.env（以仓库根启动时）
	if _, err := os.Stat(filepath.Join("server", ".env")); err == nil {
		_ = godotenv.Load(filepath.Join("server", ".env"))
	}

	secret := getEnv("JWT_SECRET", "")
	if secret == "" {
		// 开发环境：无 secret 时生成并持久化，保证重启后 token 仍有效
		secret = loadOrCreateSecret(util.RandomHex(48))
	}

	return &Config{
		Port:      getEnv("PORT", "8081"),
		DBDSN:     getEnv("DB_DSN", "root:@tcp(127.0.0.1:3306)/chord?charset=utf8mb4&parseTime=True&loc=Local"),
		// 默认尝试本机 6379（go run ./cmd/fakeredis 或真 Redis）；
		// 连不上时 bus.NewRedis 自动降级为进程内事件总线
		RedisAddr: getEnv("REDIS_ADDR", "127.0.0.1:6379"),
		JWTSecret: secret,
		SeedDemo:  getEnv("SEED_DEMO", "true") == "true",
		ClientOrigins: []string{
			getEnv("CLIENT_ORIGIN", ""),
			"http://localhost:3000",
			"http://127.0.0.1:3000",
		},
		UploadDir: getEnv("UPLOAD_DIR", "./data/uploads"),
		SendIntervalMS: getEnvInt("SEND_INTERVAL_MS", 1000),
	}
}

func getEnvInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			return n
		}
	}
	return def
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func loadOrCreateSecret(secret string) string {
	const path = ".data/jwt_secret"
	if b, err := os.ReadFile(path); err == nil && len(b) >= 32 {
		return string(b)
	}
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	_ = os.WriteFile(path, []byte(secret), 0o600)
	return secret
}

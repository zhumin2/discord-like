package main

import (
	"log"

	"github.com/gin-gonic/gin"

	"chord/server/internal/bus"
	"chord/server/internal/config"
	"chord/server/internal/db"
	"chord/server/internal/handlers"
	"chord/server/internal/ws"
)

func main() {
	cfg := config.Load()

	g, err := db.Open(cfg.DBDSN)
	if err != nil {
		log.Fatalf("[fatal] %v", err)
	}
	if cfg.SeedDemo {
		db.SeedDemo(g)
	}

	// 事件总线：Redis 可用则启用（多实例），否则进程内（单实例）
	b, rdb := bus.NewRedis(cfg.RedisAddr)
	hub := ws.NewHub(g, b, ws.NewRedisPresence(rdb), cfg.JWTSecret)
	hub.Run() // 注册总线订阅者 + presence 循环

	s := &handlers.Server{DB: g, Hub: hub, Cfg: cfg}
	r := gin.Default()
	s.RegisterRoutes(r)

	log.Printf("[chord] listening on :%s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("[fatal] %v", err)
	}
}

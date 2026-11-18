package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"chord/server/internal/auth"
	"chord/server/internal/config"
	"chord/server/internal/ws"
)

// Server 聚合依赖，注册所有 REST 路由。
type Server struct {
	DB  *gorm.DB
	Hub *ws.Hub
	Cfg *config.Config
}

func (s *Server) RegisterRoutes(r *gin.Engine) {
	r.Use(s.cors())

	r.GET("/api/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })
	r.GET("/ws", s.Hub.HandleWS)
	// 上传文件读取（文件名为不可猜测 UUID，公开可读）
	r.GET("/uploads/*filepath", s.serveUpload)

	api := r.Group("/api")
	{
		// 匿名接口：按 IP 限流（防撞库/滥注）
		api.POST("/auth/register", s.limitIP(10, time.Minute, "register"), s.Register)
		api.POST("/auth/login", s.limitIP(10, time.Minute, "login"), s.Login)

		authed := api.Group("", auth.Middleware(s.Cfg.JWTSecret))
		{
			authed.GET("/users/me", s.Me)
			authed.PATCH("/users/me", s.UpdateMe)
			authed.GET("/users/search", s.SearchUsers)

			authed.POST("/upload", s.limitUser(30, time.Minute, "upload"), s.Upload)

			authed.GET("/guilds", s.ListGuilds)
			authed.POST("/guilds", s.CreateGuild)
			authed.GET("/guilds/:id/channels", s.ListChannels)
			authed.POST("/guilds/:id/channels", s.CreateChannel)
			authed.GET("/guilds/:id/members", s.ListMembers)
			authed.DELETE("/guilds/:id/members/me", s.LeaveGuild)
			authed.POST("/guilds/:id/transfer", s.TransferGuild)
			authed.DELETE("/guilds/:id", s.DeleteGuild)
			authed.POST("/guilds/:id/invites", s.RegenInvite)
			authed.GET("/invites/:code", s.GuildPreview)
			authed.POST("/invites/:code/join", s.JoinGuild)

			authed.DELETE("/channels/:id", s.DeleteChannel)
			authed.GET("/channels/:id/messages", s.ListMessages)
			authed.POST("/channels/:id/messages", s.limitUser(20, 10*time.Second, "msg"), s.SendMessage)
			authed.GET("/channels/:id/read", s.GetReadState)
			authed.PUT("/channels/:id/read", s.PutReadState)

			authed.PATCH("/messages/:id", s.EditMessage)
			authed.DELETE("/messages/:id", s.DeleteMessage)
			authed.PUT("/messages/:id/reactions", s.AddReaction)
			authed.DELETE("/messages/:id/reactions", s.RemoveReaction)

			authed.GET("/dms", s.ListDMs)
			authed.POST("/dms/:userId", s.OpenDM)
			authed.GET("/summary", s.Summary)
		}
	}
}

func (s *Server) cors() gin.HandlerFunc {
	allow := map[string]bool{}
	for _, o := range s.Cfg.ClientOrigins {
		if o != "" {
			allow[o] = true
		}
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if len(allow) == 0 || allow[origin] || origin == "" {
			c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
			if origin != "" && allow[origin] {
				c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
			}
			c.Writer.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
			c.Writer.Header().Set("Access-Control-Allow-Headers", "Authorization,Content-Type")
			c.Writer.Header().Set("Access-Control-Max-Age", "86400")
		}
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

func fail(c *gin.Context, code int, msg string) {
	c.JSON(code, gin.H{"error": msg})
}

func trimLower(s string) string { return strings.TrimSpace(strings.ToLower(s)) }

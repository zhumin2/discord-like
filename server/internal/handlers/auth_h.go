package handlers

import (
	"math/rand"
	"strings"
	"unicode/utf8"

	"github.com/gin-gonic/gin"

	"chord/server/internal/auth"
	"chord/server/internal/models"
	"chord/server/internal/util"
)

var avatarColors = []string{
	"#5865F2", "#3BA55D", "#FAA61A", "#ED4245", "#EB459E", "#9B59B6",
	"#3498DB", "#1ABC9C", "#E67E22", "#7289DA",
}

func validUsername(s string) bool {
	if utf8.RuneCountInString(s) < 2 || utf8.RuneCountInString(s) > 20 {
		return false
	}
	for _, r := range s {
		ok := r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r == '-'
		if !ok {
			return false
		}
	}
	return true
}

type registerReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// Register 注册新账号：随机分配 4 位 discriminator（同用户名冲突时重试）。
func (s *Server) Register(c *gin.Context) {
	var req registerReq
	if err := c.ShouldBindJSON(&req); err != nil {
		fail(c, 400, "参数错误")
		return
	}
	if !validUsername(req.Username) {
		fail(c, 400, "用户名需为 2-20 位字母、数字、下划线或连字符")
		return
	}
	if len(req.Password) < 6 {
		fail(c, 400, "密码至少 6 位")
		return
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		fail(c, 500, "服务器错误")
		return
	}
	u := models.User{
		ID:           models.NewID(),
		Username:     req.Username,
		PasswordHash: hash,
		AvatarColor:  avatarColors[rand.Intn(len(avatarColors))],
	}
	for i := 0; i < 20; i++ {
		u.Discriminator = padDisc(1000 + rand.Intn(9000))
		if err := s.DB.Create(&u).Error; err == nil {
			break
		}
		if i == 19 {
			fail(c, 409, "用户名已占用，请换一个")
			return
		}
	}
	token, _ := auth.MakeToken(s.Cfg.JWTSecret, u.ID)
	c.JSON(200, gin.H{"token": token, "user": u.DTO()})
}

type loginReq struct {
	Username string `json:"username"` // 支持 name#1234 或 name
	Password string `json:"password"`
}

// Login 登录：用户名不唯一时要求带 discriminator。
func (s *Server) Login(c *gin.Context) {
	var req loginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		fail(c, 400, "参数错误")
		return
	}
	name, disc, hasDisc := strings.Cut(strings.TrimSpace(req.Username), "#")
	var users []models.User
	q := s.DB.Where("username = ?", name)
	if hasDisc {
		q = q.Where("discriminator = ?", disc)
	}
	if err := q.Limit(2).Find(&users).Error; err != nil || len(users) == 0 {
		fail(c, 401, "用户不存在")
		return
	}
	if len(users) > 1 {
		fail(c, 400, "该用户名不唯一，请使用 用户名#编号 登录")
		return
	}
	u := users[0]
	if !auth.CheckPassword(u.PasswordHash, req.Password) {
		fail(c, 401, "密码错误")
		return
	}
	token, _ := auth.MakeToken(s.Cfg.JWTSecret, u.ID)
	c.JSON(200, gin.H{"token": token, "user": u.DTO()})
}

func (s *Server) Me(c *gin.Context) {
	var u models.User
	if err := s.DB.Where("id = ?", auth.UserID(c)).First(&u).Error; err != nil {
		fail(c, 404, "用户不存在")
		return
	}
	c.JSON(200, u.DTO())
}

type userResult struct {
	models.UserDTO
	Tag string `json:"tag"`
}

// SearchUsers 按用户名前缀搜索（不含自己），用于发起新私信。
func (s *Server) SearchUsers(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		c.JSON(200, []userResult{})
		return
	}
	var users []models.User
	s.DB.Where("username LIKE ?", q+"%").Limit(10).Find(&users)
	out := make([]userResult, 0, len(users))
	for _, u := range users {
		if u.ID == auth.UserID(c) {
			continue
		}
		out = append(out, userResult{UserDTO: u.DTO(), Tag: u.Tag()})
	}
	c.JSON(200, out)
}

func padDisc(n int) string {
	s := ""
	for n > 0 {
		s = string(rune('0'+n%10)) + s
		n /= 10
	}
	for len(s) < 4 {
		s = "0" + s
	}
	return s
}

var _ = util.RandomInviteCode

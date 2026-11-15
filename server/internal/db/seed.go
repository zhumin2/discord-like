package db

import (
	"log"
	"time"

	"gorm.io/gorm"

	"chord/server/internal/auth"
	"chord/server/internal/models"
	"chord/server/internal/util"
)

// SeedDemo 在空库时创建演示账号、服务器、频道与历史消息，
// 让首次启动即可体验完整功能。可用 SEED_DEMO=false 关闭。
func SeedDemo(g *gorm.DB) {
	var n int64
	g.Model(&models.User{}).Count(&n)
	if n > 0 {
		return
	}
	log.Printf("[seed] empty database, seeding demo data...")

	type demoUser struct {
		name, pw, color string
	}
	users := []demoUser{
		{"alice", "123456", "#5865F2"},
		{"bob", "123456", "#3BA55D"},
		{"carol", "123456", "#FAA61A"},
	}
	ids := map[string]string{}
	for i, du := range users {
		hash, _ := auth.HashPassword(du.pw)
		u := models.User{
			ID:           models.NewID(),
			Username:     du.name,
			Discriminator: padDisc(1001 + i),
			PasswordHash: hash,
			AvatarColor:  du.color,
		}
		if err := g.Create(&u).Error; err != nil {
			log.Printf("[seed] create user: %v", err)
			return
		}
		ids[du.name] = u.ID
	}

	guild := models.Guild{
		ID:         models.NewID(),
		Name:       "开发者交流",
		OwnerID:    ids["alice"],
		InviteCode: "demo2024",
		IconColor:  "#5865F2",
	}
	if err := g.Create(&guild).Error; err != nil {
		log.Printf("[seed] create guild: %v", err)
		return
	}
	for _, name := range []string{"alice", "bob", "carol"} {
		g.Create(&models.GuildMember{GuildID: guild.ID, UserID: ids[name], JoinedAt: time.Now()})
	}

	type demoCh struct{ cat, name string }
	channels := []demoCh{
		{"信息", "公告"}, {"信息", "规则"},
		{"闲聊", "general"}, {"闲聊", "random"},
		{"技术", "前端"}, {"技术", "后端"},
	}
	chIDs := map[string]string{}
	for i, c := range channels {
		ch := models.Channel{ID: models.NewID(), GuildID: guild.ID, Name: c.name, Category: c.cat, Position: i}
		if err := g.Create(&ch).Error; err != nil {
			log.Printf("[seed] create channel: %v", err)
			return
		}
		chIDs[c.name] = ch.ID
	}

	base := time.Now().Add(-26 * time.Hour)
	msgs := []struct {
		ch, author, content string
		offset              time.Duration
	}{
		{"公告", "alice", "欢迎来到 **Chord** —— 一个模仿 Discord 的实时聊天社区 🎉", 1 * time.Hour},
		{"公告", "alice", "左侧选择服务器与频道，点击输入框即可发言。别忘了试试表情回应和 @ 提及。", 2 * time.Hour},
		{"规则", "alice", "友好交流，技术讨论优先，禁止灌水刷屏。", 3 * time.Hour},
		{"general", "bob", "早上好各位，今天天气不错 `☀️`", 5 * time.Hour},
		{"general", "carol", "早！刚把 **Flutter Web** 的响应式布局跑通了", 5*time.Hour + 20*time.Minute},
		{"general", "bob", "牛的，回头给我看看代码", 5*time.Hour + 25*time.Minute},
		{"general", "carol", "没问题，PC 端四栏、手机端单栏加抽屉，一套代码全搞定", 5*time.Hour + 40*time.Minute},
		{"general", "alice", "记得 @ 我提 bug：@alice#1001", 6 * time.Hour},
		{"前端", "carol", "消息列表用了 `reverse ListView`，向上滚动自动分页加载历史", 8 * time.Hour},
		{"前端", "bob", "断点设在 768px 够用吗？", 9 * time.Hour},
		{"前端", "carol", "够用，手机端还有底部安全区适配", 9*time.Hour + 30*time.Minute},
		{"后端", "bob", "Go + Gin + WebSocket 网关，事件延迟基本在毫秒级", 12 * time.Hour},
		{"后端", "alice", "MySQL 存消息，Redis 做在线状态，没有 Redis 时会自动降级为进程内实现", 12*time.Hour + 30*time.Minute},
		{"random", "carol", "投个票：今天中午吃什么 🍜", 20 * time.Hour},
		{"random", "bob", "拉面 +1", 20*time.Hour + 10*time.Minute},
	}
	for _, m := range msgs {
		g.Create(&models.Message{
			ID: models.NewID(), ChannelID: chIDs[m.ch], AuthorID: ids[m.author],
			Content: m.content, CreatedAt: base.Add(m.offset),
		})
	}
	log.Printf("[seed] done: 3 users (alice/bob/carol, 密码 123456), guild invite=demo2024, %d channels, %d messages", len(channels), len(msgs))
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

var _ = util.RandomInviteCode // 保留引用避免未使用告警

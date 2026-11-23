package db

import (
	"fmt"
	"log"
	"strconv"
	"time"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"chord/server/internal/models"
)

// Open 连接 MySQL 并执行自动迁移。
func Open(dsn string) (*gorm.DB, error) {
	g, err := gorm.Open(mysql.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	})
	if err != nil {
		return nil, fmt.Errorf("connect mysql: %w", err)
	}
	sqlDB, err := g.DB()
	if err != nil {
		return nil, err
	}
	sqlDB.SetMaxOpenConns(40)
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetConnMaxLifetime(time.Hour)

	if err := g.AutoMigrate(
		&models.User{}, &models.Guild{}, &models.GuildMember{},
		&models.Channel{}, &models.DMChannel{},
		&models.Message{}, &models.Reaction{}, &models.ReadState{},
	); err != nil {
		return nil, fmt.Errorf("migrate: %w", err)
	}
	// 老数据的 speak_mode 可能是空串（v1.3.5 之前没有该列）→ 统一补成 all，
	// 否则客户端会把它们当成"受限频道"显示锁标
	g.Model(&models.Channel{}).Where("speak_mode = '' OR speak_mode IS NULL").
		Update("speak_mode", models.SpeakAll)
	migrateUsernameUnique(g)
	log.Printf("[db] mysql connected, schema migrated")
	return g, nil
}

// migrateUsernameUnique 把「用户名必须唯一」落实到数据库：
//  1. 先把历史重复用户名改名（保留最早注册的那个，其余改成 name_discriminator）
//  2. 再补唯一索引，彻底杜绝并发注册出两个同名用户
//
// 背景：早期采用 Discord 式 username#discriminator 设计，允许同名不同编号；
// 但本产品 @提及/搜索都按用户名匹配，同名会直接导致提到谁不明确，故收紧为全局唯一。
func migrateUsernameUnique(g *gorm.DB) {
	type dupRow struct {
		Username string
		C        int
	}
	var dups []dupRow
	if err := g.Raw("SELECT username, COUNT(*) AS c FROM users GROUP BY username HAVING c > 1").Scan(&dups).Error; err != nil {
		log.Printf("[db] 检查重复用户名失败: %v", err)
		return
	}
	for _, d := range dups {
		var users []models.User
		if err := g.Where("username = ?", d.Username).Order("created_at, id").Find(&users).Error; err != nil {
			continue
		}
		for _, u := range users[1:] { // 保留最早注册的
			base := d.Username + "_" + u.Discriminator
			base = truncateRunes(base, 32)
			candidate := base
			for n := 1; n <= 100; n++ {
				var cnt int64
				g.Model(&models.User{}).Where("username = ? AND id <> ?", candidate, u.ID).Count(&cnt)
				if cnt == 0 {
					break
				}
				candidate = truncateRunes(base+"_"+strconv.Itoa(n), 32)
			}
			if err := g.Model(&models.User{}).Where("id = ?", u.ID).Update("username", candidate).Error; err == nil {
				log.Printf("[db] 重复用户名已修正: %s#%s (id=%s) → %s", d.Username, u.Discriminator, u.ID, candidate)
			}
		}
	}

	var idxCount int64
	g.Raw(`SELECT COUNT(*) FROM information_schema.statistics
	       WHERE table_schema = DATABASE() AND table_name = 'users'
	         AND index_name = 'idx_users_username'`).Scan(&idxCount)
	if idxCount == 0 {
		if err := g.Exec("ALTER TABLE users ADD UNIQUE INDEX idx_users_username (username)").Error; err != nil {
			log.Printf("[db] 创建用户名唯一索引失败: %v", err)
		} else {
			log.Printf("[db] 已创建用户名唯一索引 idx_users_username")
		}
	}
}

// truncateRunes 按字符（不是字节）截断，避免截断中文。
func truncateRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max])
}

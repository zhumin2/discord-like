package db

import (
	"fmt"
	"log"
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
	log.Printf("[db] mysql connected, schema migrated")
	return g, nil
}

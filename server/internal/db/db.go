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
	log.Printf("[db] mysql connected, schema migrated")
	return g, nil
}

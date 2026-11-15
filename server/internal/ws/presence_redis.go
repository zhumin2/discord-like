package ws

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisPresence 允许 Hub 在多实例部署时通过 Redis 感知其他实例的在线状态。
// 单实例（无 Redis）时为 nil。
type RedisPresence interface {
	IsOnline(userID string) bool
	SetPresence(userID string, online bool)
}

type redisPresence struct{ rdb *redis.Client }

func NewRedisPresence(rdb *redis.Client) RedisPresence {
	if rdb == nil {
		return nil
	}
	return &redisPresence{rdb: rdb}
}

func ctx() context.Context { return context.Background() }

func (r *redisPresence) IsOnline(userID string) bool {
	n, err := r.rdb.Exists(ctx(), "presence:"+userID).Result()
	return err == nil && n > 0
}

func (r *redisPresence) SetPresence(userID string, online bool) {
	key := "presence:" + userID
	if online {
		r.rdb.Set(ctx(), key, "1", 60*time.Second)
	} else {
		r.rdb.Del(ctx(), key)
	}
}

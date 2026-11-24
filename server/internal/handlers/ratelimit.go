package handlers

import (
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// ---- 固定窗口限流器（单实例内存版；多实例时可切换 Redis 实现） ----

type rlBucket struct {
	count int
	start time.Time
}

type rateLimiter struct {
	mu      sync.Mutex
	max     int
	window  time.Duration
	buckets map[string]*rlBucket
}

func newRateLimiter(max int, window time.Duration) *rateLimiter {
	return &rateLimiter{max: max, window: window, buckets: map[string]*rlBucket{}}
}

// allow 惰性过期：窗口未满则计数+1 并放行；越界返回 false。
func (l *rateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	b, ok := l.buckets[key]
	if !ok || now.Sub(b.start) >= l.window {
		// 顺带做一次低成本的过期清理，防止 map 无限增长
		if len(l.buckets) > 4096 {
			for k, v := range l.buckets {
				if now.Sub(v.start) >= l.window {
					delete(l.buckets, k)
				}
			}
		}
		l.buckets[key] = &rlBucket{count: 1, start: now}
		return true
	}
	b.count++
	return b.count <= l.max
}

// ---- 最小发言间隔（cooldown）----
// 固定窗口限流允许瞬间打满配额（20 条/10s 可在 1s 内全部发出），
// 为防接入 AI 后被高频灌水，另加「同一用户两条消息至少间隔 N 毫秒」的硬限制。

type cooldownLimiter struct {
	mu       sync.Mutex
	interval time.Duration
	last     map[string]time.Time
}

func newCooldownLimiter(interval time.Duration) *cooldownLimiter {
	return &cooldownLimiter{interval: interval, last: map[string]time.Time{}}
}

// blocked 只判断不记录：距上次**成功**发言不足 interval 则为 true。
func (l *cooldownLimiter) blocked(key string) bool {
	if l.interval <= 0 {
		return false
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	t, ok := l.last[key]
	return ok && time.Since(t) < l.interval
}

// mark 记录一次成功发言的时间。
func (l *cooldownLimiter) mark(key string) {
	if l.interval <= 0 {
		return
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	l.last[key] = time.Now()
}

// allow 记录并判断：距上次发言不足 interval 则拒绝。
func (l *cooldownLimiter) allow(key string) bool {
	if l.interval <= 0 {
		return true
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	if t, ok := l.last[key]; ok && now.Sub(t) < l.interval {
		return false
	}
	l.last[key] = now
	// 低成本清理，防止 map 无限增长
	if len(l.last) > 8192 {
		for k, t := range l.last {
			if now.Sub(t) > l.interval {
				delete(l.last, k)
			}
		}
	}
	return true
}

// limitIP 按 IP 限流（用于匿名接口：注册/登录）。
func (s *Server) limitIP(max int, window time.Duration, scope string) gin.HandlerFunc {
	l := newRateLimiter(max, window)
	return func(c *gin.Context) {
		if !l.allow(c.ClientIP() + "|" + scope) {
			c.AbortWithStatusJSON(429, gin.H{"error": "操作过于频繁，请稍后再试"})
			return
		}
		c.Next()
	}
}

// limitUser 按用户 ID 限流（用于登录后接口：发消息/上传）。
func (s *Server) limitUser(max int, window time.Duration, scope string) gin.HandlerFunc {
	l := newRateLimiter(max, window)
	return func(c *gin.Context) {
		uid := c.GetString("userID")
		if uid == "" {
			uid = c.ClientIP()
		}
		if !l.allow(uid + "|" + scope) {
			c.AbortWithStatusJSON(429, gin.H{"error": "操作过于频繁，请稍后再试"})
			return
		}
		c.Next()
	}
}

package bus

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// Envelope 是跨实例广播的事件信封：实例间通过 Redis pub/sub 交换，
// 收到后由本实例的订阅者（Hub）转发给本地连接。
// 单实例（无 Redis）时 MemoryBus 直接进程内回调，行为一致。
type Envelope struct {
	Topic string `json:"topic"` // guild:<id> / dm:<channelId> / user:<id>
	Data  []byte `json:"data"`
}

// Handler 收到订阅消息时的回调。
type Handler func(env Envelope)

// Bus 是事件总线抽象：Publish 的消息会投递给所有实例（含本实例）的订阅者。
type Bus interface {
	Publish(env Envelope)
	Subscribe(h Handler)
	Close() error
}

// NewRedis 创建 Redis 总线；addr 为空或连接失败时降级为内存总线。
// 返回的 *redis.Client 可为 nil（未使用 Redis）。
func NewRedis(addr string) (Bus, *redis.Client) {
	if addr == "" {
		log.Printf("[bus] REDIS_ADDR 未设置，使用进程内事件总线（单实例模式）")
		return NewMemory(), nil
	}
	rdb := redis.NewClient(&redis.Options{Addr: addr, DialTimeout: 2 * time.Second})
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Printf("[bus] Redis 不可达(%v)，降级为进程内事件总线", err)
		_ = rdb.Close()
		return NewMemory(), nil
	}
	rb := &redisBus{rdb: rdb, chanName: "chord:events"}
	go rb.loop()
	log.Printf("[bus] Redis 事件总线已连接: %s", addr)
	return rb, rdb
}

func marshal(env Envelope) ([]byte, error)  { return json.Marshal(env) }
func unmarshal(b []byte) (Envelope, bool) {
	var env Envelope
	if err := json.Unmarshal(b, &env); err != nil {
		return Envelope{}, false
	}
	return env, true
}

// ---------- 内存实现 ----------

type MemoryBus struct {
	mu   sync.RWMutex
	subs []Handler
}

func NewMemory() *MemoryBus { return &MemoryBus{} }

func (b *MemoryBus) Subscribe(h Handler) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.subs = append(b.subs, h)
}

func (b *MemoryBus) Publish(env Envelope) {
	b.mu.RLock()
	subs := append([]Handler(nil), b.subs...)
	b.mu.RUnlock()
	for _, h := range subs {
		h(env)
	}
}

func (b *MemoryBus) Close() error { return nil }

// ---------- Redis 实现 ----------

type redisBus struct {
	rdb      *redis.Client
	chanName string

	mu   sync.RWMutex
	subs []Handler
}

func (b *redisBus) Subscribe(h Handler) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.subs = append(b.subs, h)
}

func (b *redisBus) Publish(env Envelope) {
	payload, err := marshal(env)
	if err != nil {
		return
	}
	b.rdb.Publish(context.Background(), b.chanName, payload)
}

func (b *redisBus) loop() {
	sub := b.rdb.Subscribe(context.Background(), b.chanName)
	defer sub.Close()
	for msg := range sub.Channel() {
		env, ok := unmarshal([]byte(msg.Payload))
		if !ok {
			continue
		}
		b.mu.RLock()
		subs := append([]Handler(nil), b.subs...)
		b.mu.RUnlock()
		for _, h := range subs {
			h(env)
		}
	}
}

func (b *redisBus) Close() error { return b.rdb.Close() }

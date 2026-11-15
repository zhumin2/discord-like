// redisprobe：连接 Redis 打印当前状态，用于验证 API 是否真的在使用 Redis。
// 用法: go run ./cmd/redisprobe [addr]
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
)

func main() {
	addr := "127.0.0.1:6379"
	args := os.Args
	if len(args) > 2 {
		addr = args[2]
	}
	rdb := redis.NewClient(&redis.Options{Addr: addr})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if len(args) > 1 && args[1] == "-sub" {
		subscribeOnce(rdb)
		return
	}

	if err := rdb.Ping(ctx).Err(); err != nil {
		fmt.Printf("PING %s -> FAIL: %v\n", addr, err)
		return
	}
	fmt.Printf("PING %s -> PONG\n", addr)

	keys, err := rdb.Keys(ctx, "presence:*").Result()
	if err != nil {
		fmt.Println("KEYS presence:* ->", err)
		return
	}
	fmt.Printf("presence keys (%d):\n", len(keys))
	for _, k := range keys {
		v, _ := rdb.Get(ctx, k).Result()
		fmt.Printf("  %s = %s\n", k, v)
	}
}

// subscribeOnce 订阅 chord:events 频道 5 秒，打印收到的事件（验证 pub/sub 链路）。
func subscribeOnce(rdb *redis.Client) {
	ctx := context.Background()
	sub := rdb.Subscribe(ctx, "chord:events")
	defer sub.Close()
	fmt.Println("SUB chord:events ... (等待事件最多 5 秒)")
	ch := sub.Channel()
	select {
	case msg := <-ch:
		payload := msg.Payload
		if len(payload) > 150 {
			payload = payload[:150] + "..."
		}
		fmt.Printf("SUB RECEIVED: %s\n", payload)
	case <-time.After(5 * time.Second):
		fmt.Println("SUB: 5 秒内无事件（发送一条消息后再试）")
	}
}

// fakeredis：基于 miniredis 的 Redis 协议兼容开发服务器。
// 用途：让本机开发环境真正走到 go-redis 客户端 + Redis 代码路径
// （在线状态键、事件 pub/sub），无需安装真 Redis / Docker / WSL。
// 注意：数据在内存中，重启即失——presence/typing 本来就是临时数据。
// 生产多实例部署请使用真 Redis（REDIS_ADDR 指向它）。
package main

import (
	"io"
	"log"
	"net"

	mr "github.com/alicebob/miniredis/v2"
)

func main() {
	// miniredis 只支持随机端口，这里在其前挡一层 TCP 透传，固定监听 6379
	s, err := mr.Run()
	if err != nil {
		log.Fatalf("[fakeredis] 启动 miniredis 失败: %v", err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:6379")
	if err != nil {
		log.Fatalf("[fakeredis] 监听 6379 失败（端口被占用？）: %v", err)
	}
	log.Printf("[fakeredis] Redis 兼容服务器已就绪: 127.0.0.1:6379 -> %s（Ctrl+C 退出）", s.Addr())

	for {
		client, err := ln.Accept()
		if err != nil {
			log.Printf("[fakeredis] accept: %v", err)
			continue
		}
		go func(c net.Conn) {
			upstream, err := net.Dial("tcp", s.Addr())
			if err != nil {
				_ = c.Close()
				return
			}
			go io.Copy(upstream, c)
			_, _ = io.Copy(c, upstream)
			_ = c.Close()
			_ = upstream.Close()
		}(client)
	}
}

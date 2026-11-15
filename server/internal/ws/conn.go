package ws

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"chord/server/internal/auth"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 70 * time.Second
	pingPeriod = 25 * time.Second
	sendBuffer = 256
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 4096,
	CheckOrigin:     func(*http.Request) bool { return true }, // 鉴权靠 token
}

// Conn 是一条已鉴权的 WebSocket 连接。
type Conn struct {
	hub    *Hub
	sock   *websocket.Conn
	UserID string
	send   chan []byte
	closeOnce chan struct{}
}

// HandleWS 处理 /ws?token= 升级请求。
func (h *Hub) HandleWS(c *gin.Context) {
	token := c.Query("token")
	uid, err := auth.ParseToken(h.JWTSecret, token)
	if err != nil || uid == "" {
		c.JSON(401, gin.H{"error": "invalid token"})
		return
	}
	sock, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	conn := &Conn{
		hub: h, sock: sock, UserID: uid,
		send: make(chan []byte, sendBuffer),
		closeOnce: make(chan struct{}),
	}
	h.register(conn)
	go conn.writePump()
	go conn.readPump()
}

// push 非阻塞投递；队列满则丢弃（写入泵会随连接关闭而退出）。
func (c *Conn) push(data []byte) {
	select {
	case c.send <- data:
	case <-c.closeOnce:
	default:
		log.Printf("[ws] send buffer full, dropping message for %s", c.UserID)
	}
}

func (c *Conn) close() {
	select {
	case <-c.closeOnce:
	default:
		close(c.closeOnce)
	}
}

func (c *Conn) readPump() {
	defer func() {
		c.hub.unregister(c)
		c.close()
		_ = c.sock.Close()
	}()
	c.sock.SetReadDeadline(time.Now().Add(pongWait))
	c.sock.SetPongHandler(func(string) error {
		c.sock.SetReadDeadline(time.Now().Add(pongWait))
		c.hub.SetActivity(c.UserID)
		return nil
	})
	for {
		_, raw, err := c.sock.ReadMessage()
		if err != nil {
			return
		}
		c.sock.SetReadDeadline(time.Now().Add(pongWait))
		var msg Envelope
		if err := json.Unmarshal(raw, &msg); err != nil {
			continue
		}
		switch msg.T {
		case "heartbeat":
			c.hub.SetActivity(c.UserID)
			c.push([]byte(`{"t":"HEARTBEAT_ACK"}`))
		case "typing":
			var d struct {
				ChannelID string `json:"channelId"`
			}
			if json.Unmarshal(msg.D, &d) == nil && d.ChannelID != "" {
				c.hub.HandleTyping(c.UserID, d.ChannelID)
			}
		}
	}
}

func (c *Conn) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		_ = c.sock.Close()
	}()
	for {
		select {
		case data := <-c.send:
			c.sock.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.sock.WriteMessage(websocket.TextMessage, data); err != nil {
				return
			}
		case <-ticker.C:
			c.sock.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.sock.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		case <-c.closeOnce:
			return
		}
	}
}

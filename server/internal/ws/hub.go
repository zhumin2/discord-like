package ws

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"gorm.io/gorm"

	"chord/server/internal/bus"
	"chord/server/internal/models"
)

// 事件类型（服务端 → 客户端）
const (
	EvReady           = "READY"
	EvMessageCreate   = "MESSAGE_CREATE"
	EvMessageUpdate   = "MESSAGE_UPDATE"
	EvMessageDelete   = "MESSAGE_DELETE"
	EvReactionAdd     = "REACTION_ADD"
	EvReactionRemove  = "REACTION_REMOVE"
	EvTypingStart     = "TYPING_START"
	EvPresenceUpdate  = "PRESENCE_UPDATE"
	EvChannelCreated  = "CHANNEL_CREATED"
	EvChannelDeleted  = "CHANNEL_DELETED"
	EvMemberJoined    = "MEMBER_JOINED"
	EvMemberLeft      = "MEMBER_LEFT"
	EvGuildDeleted    = "GUILD_DELETED"
	EvDMCreated       = "DM_CREATED"
	EvUserUpdate      = "USER_UPDATE"
)

// Envelope 是发往客户端的事件信封。
type Envelope struct {
	T string          `json:"t"`
	D json.RawMessage `json:"d,omitempty"`
}

func NewEnvelope(t string, d any) Envelope {
	b, _ := json.Marshal(d)
	return Envelope{T: t, D: b}
}

type guildCacheEntry struct {
	ids []string
	exp time.Time
}

type dmCacheEntry struct {
	pair [2]string
	exp  time.Time
}

// Hub 管理所有 WebSocket 连接、事件路由与在线状态。
type Hub struct {
	DB        *gorm.DB
	Bus       bus.Bus
	RDB       RedisPresence // 可为 nil（无 Redis）
	JWTSecret string

	mu       sync.RWMutex
	conns    map[string]map[*Conn]bool // userID -> conns
	activity map[string]time.Time      // userID -> 最近活动时间（心跳/typing）
	guilds   map[string]guildCacheEntry
	dms      map[string]dmCacheEntry
	typing   map[string]time.Time // "user|channel" -> 上次广播时间（节流）

	stop chan struct{}
}

func NewHub(db *gorm.DB, b bus.Bus, rdb RedisPresence, jwtSecret string) *Hub {
	return &Hub{
		DB: db, Bus: b, RDB: rdb, JWTSecret: jwtSecret,
		conns:    map[string]map[*Conn]bool{},
		activity: map[string]time.Time{},
		guilds:   map[string]guildCacheEntry{},
		dms:      map[string]dmCacheEntry{},
		typing:   map[string]time.Time{},
		stop:     make(chan struct{}),
	}
}

// Run 启动 presence 扫描循环并注册总线订阅。
func (h *Hub) Run() {
	h.Bus.Subscribe(func(env bus.Envelope) {
		h.DeliverLocal(env.Topic, env.Data)
	})
	go h.presenceLoop()
}

func (h *Hub) Stop() { close(h.stop) }

// ---------- 连接注册 ----------

func (h *Hub) register(c *Conn) {
	first := false
	h.mu.Lock()
	if h.conns[c.UserID] == nil {
		h.conns[c.UserID] = map[*Conn]bool{}
	}
	if len(h.conns[c.UserID]) == 0 {
		first = true
	}
	h.conns[c.UserID][c] = true
	h.activity[c.UserID] = time.Now()
	h.mu.Unlock()
	if first {
		h.BroadcastPresence(c.UserID, "online")
	}
}

func (h *Hub) unregister(c *Conn) {
	last := false
	h.mu.Lock()
	if set := h.conns[c.UserID]; set != nil {
		delete(set, c)
		if len(set) == 0 {
			delete(h.conns, c.UserID)
			delete(h.activity, c.UserID)
			last = true
		}
	}
	h.mu.Unlock()
	if last {
		h.BroadcastPresence(c.UserID, "offline")
	}
}

// OnlineConns 返回某用户当前本地连接数。
func (h *Hub) connCount(userID string) int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.conns[userID])
}

// HasConnection 本地有连接即在线；配合 Redis 键可感知其他实例的连接。
func (h *Hub) IsOnline(userID string) bool {
	if h.connCount(userID) > 0 {
		return true
	}
	if h.RDB != nil {
		return h.RDB.IsOnline(userID)
	}
	return false
}

// ---------- 受众解析 ----------

// GuildMemberIDs 返回成员 ID 列表（30s 缓存）。
func (h *Hub) GuildMemberIDs(guildID string) []string {
	h.mu.RLock()
	if e, ok := h.guilds[guildID]; ok && time.Now().Before(e.exp) {
		h.mu.RUnlock()
		return e.ids
	}
	h.mu.RUnlock()

	var ids []string
	h.DB.Model(&models.GuildMember{}).Where("guild_id = ?", guildID).Pluck("user_id", &ids)

	h.mu.Lock()
	h.guilds[guildID] = guildCacheEntry{ids: ids, exp: time.Now().Add(30 * time.Second)}
	h.mu.Unlock()
	return ids
}

func (h *Hub) InvalidateGuild(guildID string) {
	h.mu.Lock()
	delete(h.guilds, guildID)
	h.mu.Unlock()
}

// DMPair 返回私信双方 userID（5min 缓存）。
func (h *Hub) DMPair(channelID string) ([2]string, bool) {
	h.mu.RLock()
	if e, ok := h.dms[channelID]; ok && time.Now().Before(e.exp) {
		h.mu.RUnlock()
		return e.pair, true
	}
	h.mu.RUnlock()

	var dm models.DMChannel
	if err := h.DB.Where("id = ?", channelID).First(&dm).Error; err != nil {
		return [2]string{}, false
	}
	pair := [2]string{dm.UserAID, dm.UserBID}
	h.mu.Lock()
	h.dms[channelID] = dmCacheEntry{pair: pair, exp: time.Now().Add(5 * time.Minute)}
	h.mu.Unlock()
	return pair, true
}

// ---------- 事件投递 ----------

// deliverToUsers 将事件推给指定用户的所有本地连接。
func (h *Hub) deliverToUsers(userIDs []string, env Envelope) {
	data, _ := json.Marshal(env)
	h.mu.RLock()
	var targets []*Conn
	for _, uid := range userIDs {
		for c := range h.conns[uid] {
			targets = append(targets, c)
		}
	}
	h.mu.RUnlock()
	for _, c := range targets {
		c.push(data)
	}
}

// DeliverLocal 处理总线投递的事件：解析 topic → 本地受众 → 推送。
func (h *Hub) DeliverLocal(topic string, raw json.RawMessage) {
	var env Envelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return
	}
	var users []string
	switch {
	case len(topic) > 6 && topic[:6] == "guild:":
		users = h.GuildMemberIDs(topic[6:])
	case len(topic) > 3 && topic[:3] == "dm:":
		if pair, ok := h.DMPair(topic[3:]); ok {
			users = pair[:]
		}
	case len(topic) > 5 && topic[:5] == "user:":
		users = []string{topic[5:]}
	default:
		return
	}
	h.deliverToUsers(users, env)
}

// Broadcast 向 topic 受众广播事件（本地 + 跨实例）。
func (h *Hub) Broadcast(topic string, env Envelope) {
	data, _ := json.Marshal(env)
	h.Bus.Publish(bus.Envelope{Topic: topic, Data: data})
}

// ChannelTopic 返回频道所属 topic；unknown 返回 false。
func (h *Hub) ChannelTopic(channelID string) (string, bool) {
	var guildID string
	err := h.DB.Model(&models.Channel{}).Select("guild_id").Where("id = ?", channelID).Scan(&guildID).Error
	if err == nil && guildID != "" {
		return "guild:" + guildID, true
	}
	if _, ok := h.DMPair(channelID); ok {
		return "dm:" + channelID, true
	}
	return "", false
}

// ---------- typing ----------

func (h *Hub) HandleTyping(userID, channelID string) {
	key := userID + "|" + channelID
	h.mu.Lock()
	if time.Since(h.typing[key]) < 4*time.Second {
		h.mu.Unlock()
		return
	}
	h.typing[key] = time.Now()
	h.activity[userID] = time.Now()
	h.mu.Unlock()

	topic, ok := h.ChannelTopic(channelID)
	if !ok {
		return
	}
	var u models.User
	if err := h.DB.Where("id = ?", userID).First(&u).Error; err != nil {
		return
	}
	h.Broadcast(topic, NewEnvelope(EvTypingStart, map[string]any{
		"channelId": channelID, "userId": userID, "username": u.Username,
	}))
}

// ---------- presence ----------

func (h *Hub) SetActivity(userID string) {
	h.mu.Lock()
	h.activity[userID] = time.Now()
	h.mu.Unlock()
	// 心跳同时为 Redis 在线键续期（TTL 60s），
	// 否则长连接用户会在多实例部署下被其他实例误判为离线
	if h.RDB != nil {
		h.RDB.SetPresence(userID, true)
	}
}

// PresenceStatus 返回用户当前状态：online / idle / offline。
func (h *Hub) PresenceStatus(userID string) string {
	h.mu.RLock()
	_, connected := h.conns[userID]
	last, hasAct := h.activity[userID]
	h.mu.RUnlock()
	if !connected {
		if h.RDB != nil && h.RDB.IsOnline(userID) {
			return "online"
		}
		return "offline"
	}
	if hasAct && time.Since(last) > 3*time.Minute {
		return "idle"
	}
	return "online"
}

// BroadcastPresence 通知与该用户共享服务器/私信的所有在线用户。
func (h *Hub) BroadcastPresence(userID, status string) {
	if h.RDB != nil {
		h.RDB.SetPresence(userID, status != "offline")
	}
	var guildIDs []string
	h.DB.Model(&models.GuildMember{}).Where("user_id = ?", userID).Pluck("guild_id", &guildIDs)
	env := NewEnvelope(EvPresenceUpdate, map[string]any{"userId": userID, "status": status})
	for _, gid := range guildIDs {
		h.Broadcast("guild:"+gid, env)
	}
	// 私信对端
	var dmIDs []string
	h.DB.Model(&models.DMChannel{}).
		Where("user_a_id = ? OR user_b_id = ?", userID, userID).Pluck("id", &dmIDs)
	for _, id := range dmIDs {
		h.Broadcast("dm:"+id, env)
	}
}

// presenceLoop 周期性检查空闲状态变化（online → idle）。
func (h *Hub) presenceLoop() {
	t := time.NewTicker(30 * time.Second)
	defer t.Stop()
	prev := map[string]string{}
	for {
		select {
		case <-h.stop:
			return
		case <-t.C:
			h.mu.RLock()
			users := make([]string, 0, len(h.conns))
			for uid := range h.conns {
				users = append(users, uid)
			}
			h.mu.RUnlock()
			for _, uid := range users {
				cur := h.PresenceStatus(uid)
				if prev[uid] != cur && cur != "" {
					prev[uid] = cur
					if cur == "idle" {
						h.BroadcastPresence(uid, cur)
						log.Printf("[hub] %s -> idle", uid)
					}
				}
			}
		}
	}
}

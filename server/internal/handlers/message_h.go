package handlers

import (
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"chord/server/internal/auth"
	"chord/server/internal/models"
	"chord/server/internal/ws"
)

// ---------- 频道/DM 权限辅助 ----------

func (s *Server) canAccessChannel(userID, channelID string) (string, bool) {
	// 频道消息
	var guildID string
	err := s.DB.Model(&models.Channel{}).Select("guild_id").
		Where("id = ?", channelID).Scan(&guildID).Error
	if err == nil && guildID != "" {
		return "guild:" + guildID, s.isMember(userID, guildID)
	}
	// DM
	var dm models.DMChannel
	if err := s.DB.Where("id = ?", channelID).First(&dm).Error; err == nil {
		if dm.UserAID == userID || dm.UserBID == userID {
			return "dm:" + channelID, true
		}
	}
	return "", false
}

// ---------- 消息富化 ----------

type reactionSummary = models.ReactionSummary

func (s *Server) attachExtras(msgs []models.Message, viewerID string) {
	if len(msgs) == 0 {
		return
	}
	ids := make([]string, len(msgs))
	authorIDs := make([]string, 0, len(msgs))
	seenAuthor := map[string]bool{}
	replyIDs := make([]string, 0, len(msgs))
	seenReply := map[string]bool{}
	for i, m := range msgs {
		ids[i] = m.ID
		if !seenAuthor[m.AuthorID] {
			seenAuthor[m.AuthorID] = true
			authorIDs = append(authorIDs, m.AuthorID)
		}
		if m.ReplyToID != "" && !seenReply[m.ReplyToID] {
			seenReply[m.ReplyToID] = true
			replyIDs = append(replyIDs, m.ReplyToID)
		}
	}
	// 作者
	var authors []models.User
	s.DB.Where("id IN ?", authorIDs).Find(&authors)
	amap := map[string]models.UserDTO{}
	for _, a := range authors {
		amap[a.ID] = a.DTO()
	}
	// 回应
	var reacts []models.Reaction
	s.DB.Where("message_id IN ?", ids).Order("created_at").Find(&reacts)
	rmap := map[string][]reactionSummary{}
	for _, r := range reacts {
		list := rmap[r.MessageID]
		found := false
		for i := range list {
			if list[i].Emoji == r.Emoji {
				list[i].Count++
				list[i].Mine = list[i].Mine || r.UserID == viewerID
				if len(list[i].Users) < 3 {
					list[i].Users = append(list[i].Users, r.UserID)
				}
				found = true
				break
			}
		}
		if !found {
			list = append(list, reactionSummary{
				Emoji: r.Emoji, Count: 1, Mine: r.UserID == viewerID,
				Users: []string{r.UserID},
			})
		}
		rmap[r.MessageID] = list
	}
	for i := range msgs {
		if a, ok := amap[msgs[i].AuthorID]; ok {
			dto := a
			msgs[i].Author = &dto
		}
	}

	// 被引用的消息（摘要预览）
	replyMap := map[string]*models.ReplyPreview{}
	if len(replyIDs) > 0 {
		var quoted []models.Message
		s.DB.Where("id IN ?", replyIDs).Find(&quoted)
		qAuthorIDs := make([]string, 0, len(quoted))
		seenQ := map[string]bool{}
		for _, q := range quoted {
			if !seenQ[q.AuthorID] {
				seenQ[q.AuthorID] = true
				qAuthorIDs = append(qAuthorIDs, q.AuthorID)
			}
		}
		var qAuthors []models.User
		s.DB.Where("id IN ?", qAuthorIDs).Find(&qAuthors)
		qmap := map[string]models.User{}
		for _, a := range qAuthors {
			qmap[a.ID] = a
		}
		for _, q := range quoted {
			name, color := "未知用户", "#5865F2"
			if a, ok := qmap[q.AuthorID]; ok {
				name, color = a.Username, a.AvatarColor
			}
			replyMap[q.ID] = &models.ReplyPreview{
				ID: q.ID, AuthorName: name, AuthorColor: color,
				Content: truncateRunes(q.Content, 120),
			}
		}
	}

	for i := range msgs {
		if list := rmap[msgs[i].ID]; len(list) > 0 {
			msgs[i].ReactionSummaries = list
		} else {
			msgs[i].ReactionSummaries = []reactionSummary{}
		}
		if p, ok := replyMap[msgs[i].ReplyToID]; ok {
			msgs[i].ReplyTo = p
		}
	}
}

// truncateRunes 按字符（而非字节）截断，避免切坏中文/emoji。
func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}

// ---------- 消息 CRUD ----------

// ListMessages 历史消息：?before=<messageID>&limit=50，返回按时间正序的 50 条（含作者与回应）。
func (s *Server) ListMessages(c *gin.Context) {
	uid := auth.UserID(c)
	cid := c.Param("id")
	if _, ok := s.canAccessChannel(uid, cid); !ok {
		fail(c, 403, "无权访问该频道")
		return
	}
	limit := 50
	if v := c.Query("limit"); v == "20" || v == "100" {
		// 仅允许几个档位，避免滥用
		limit = map[string]int{"20": 20, "100": 100}[v]
	}
	q := s.DB.Where("channel_id = ?", cid)
	if before := c.Query("before"); before != "" {
		q = q.Where("id < ?", before)
	}
	var msgs []models.Message
	if err := q.Order("id DESC").Limit(limit).Find(&msgs).Error; err != nil {
		fail(c, 500, "查询失败")
		return
	}
	// 反转为正序
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	s.attachExtras(msgs, uid)
	c.JSON(200, msgs)
}

type sendMsgReq struct {
	Content   string `json:"content"`
	ReplyToID string `json:"replyToId"` // 引用回复（可选）
}

// SendMessage 发送消息（频道或 DM），广播 MESSAGE_CREATE。
func (s *Server) SendMessage(c *gin.Context) {
	uid := auth.UserID(c)
	cid := c.Param("id")
	topic, ok := s.canAccessChannel(uid, cid)
	if !ok {
		fail(c, 403, "无权访问该频道")
		return
	}
	var req sendMsgReq
	if err := c.ShouldBindJSON(&req); err != nil {
		fail(c, 400, "参数错误")
		return
	}
	content := strings.TrimSpace(req.Content)
	if content == "" || len([]rune(content)) > 2000 {
		fail(c, 400, "消息需为 1-2000 个字符")
		return
	}
	// 引用目标必须存在且属于同一频道（防止跨频道引用泄漏）
	replyToID := strings.TrimSpace(req.ReplyToID)
	if replyToID != "" {
		var quoted models.Message
		if err := s.DB.Where("id = ? AND channel_id = ?", replyToID, cid).First(&quoted).Error; err != nil {
			fail(c, 400, "被引用的消息不存在")
			return
		}
	}
	msg := models.Message{
		ID: models.NewID(), ChannelID: cid, AuthorID: uid, Content: content,
		ReplyToID: replyToID, CreatedAt: time.Now(),
	}
	if err := s.DB.Create(&msg).Error; err != nil {
		fail(c, 500, "发送失败")
		return
	}
	// 统一补齐作者 / 回应 / 引用摘要后再广播
	one := []models.Message{msg}
	s.attachExtras(one, uid)
	msg = one[0]
	s.Hub.Broadcast(topic, ws.NewEnvelope(ws.EvMessageCreate, msg))
	c.JSON(200, msg)
}

// EditMessage 编辑自己的消息。
func (s *Server) EditMessage(c *gin.Context) {
	uid := auth.UserID(c)
	mid := c.Param("id")
	var msg models.Message
	if err := s.DB.Where("id = ?", mid).First(&msg).Error; err != nil {
		fail(c, 404, "消息不存在")
		return
	}
	if msg.AuthorID != uid {
		fail(c, 403, "只能编辑自己的消息")
		return
	}
	var req sendMsgReq
	if err := c.ShouldBindJSON(&req); err != nil {
		fail(c, 400, "参数错误")
		return
	}
	content := strings.TrimSpace(req.Content)
	if content == "" || len([]rune(content)) > 2000 {
		fail(c, 400, "消息需为 1-2000 个字符")
		return
	}
	now := time.Now()
	s.DB.Model(&msg).Updates(map[string]any{"content": content, "edited_at": now})
	msg.Content, msg.EditedAt = content, &now
	s.attachExtras([]models.Message{msg}, uid)
	topic, _ := s.Hub.ChannelTopic(msg.ChannelID)
	if topic != "" {
		s.Hub.Broadcast(topic, ws.NewEnvelope(ws.EvMessageUpdate, msg))
	}
	c.JSON(200, msg)
}

// DeleteMessage 删除自己的消息。
func (s *Server) DeleteMessage(c *gin.Context) {
	uid := auth.UserID(c)
	mid := c.Param("id")
	var msg models.Message
	if err := s.DB.Where("id = ?", mid).First(&msg).Error; err != nil {
		fail(c, 404, "消息不存在")
		return
	}
	if msg.AuthorID != uid {
		fail(c, 403, "只能删除自己的消息")
		return
	}
	s.DB.Where("message_id = ?", mid).Delete(&models.Reaction{})
	s.DB.Delete(&msg)
	topic, _ := s.Hub.ChannelTopic(msg.ChannelID)
	if topic != "" {
		s.Hub.Broadcast(topic, ws.NewEnvelope(ws.EvMessageDelete, map[string]string{
			"channelId": msg.ChannelID, "id": mid,
		}))
	}
	c.JSON(200, gin.H{"ok": true})
}

// ---------- 表情回应 ----------

type reactionReq struct {
	Emoji string `json:"emoji"`
}

func (s *Server) AddReaction(c *gin.Context) {
	uid := auth.UserID(c)
	mid := c.Param("id")
	var req reactionReq
	if err := c.ShouldBindJSON(&req); err != nil || req.Emoji == "" || len(req.Emoji) > 32 {
		fail(c, 400, "emoji 无效")
		return
	}
	var msg models.Message
	if err := s.DB.Where("id = ?", mid).First(&msg).Error; err != nil {
		fail(c, 404, "消息不存在")
		return
	}
	topic, ok := s.canAccessChannel(uid, msg.ChannelID)
	if !ok {
		fail(c, 403, "无权访问该频道")
		return
	}
	r := models.Reaction{ID: models.NewID(), MessageID: mid, UserID: uid, Emoji: req.Emoji, CreatedAt: time.Now()}
	if err := s.DB.Create(&r).Error; err != nil {
		// 已存在则幂等成功
		c.JSON(200, gin.H{"ok": true})
		return
	}
	s.Hub.Broadcast(topic, ws.NewEnvelope(ws.EvReactionAdd, map[string]string{
		"messageId": mid, "channelId": msg.ChannelID, "userId": uid, "emoji": req.Emoji,
	}))
	c.JSON(200, gin.H{"ok": true})
}

func (s *Server) RemoveReaction(c *gin.Context) {
	uid := auth.UserID(c)
	mid := c.Param("id")
	emoji := c.Query("emoji")
	if emoji == "" {
		fail(c, 400, "emoji 无效")
		return
	}
	var msg models.Message
	if err := s.DB.Where("id = ?", mid).First(&msg).Error; err != nil {
		fail(c, 404, "消息不存在")
		return
	}
	topic, ok := s.canAccessChannel(uid, msg.ChannelID)
	if !ok {
		fail(c, 403, "无权访问该频道")
		return
	}
	res := s.DB.Where("message_id = ? AND user_id = ? AND emoji = ?", mid, uid, emoji).Delete(&models.Reaction{})
	if res.RowsAffected == 0 {
		c.JSON(200, gin.H{"ok": true})
		return
	}
	s.Hub.Broadcast(topic, ws.NewEnvelope(ws.EvReactionRemove, map[string]string{
		"messageId": mid, "channelId": msg.ChannelID, "userId": uid, "emoji": emoji,
	}))
	c.JSON(200, gin.H{"ok": true})
}

// ---------- 已读状态 ----------

func (s *Server) GetReadState(c *gin.Context) {
	uid := auth.UserID(c)
	cid := c.Param("id")
	var rs models.ReadState
	if err := s.DB.Where("user_id = ? AND channel_id = ?", uid, cid).First(&rs).Error; err != nil {
		c.JSON(200, gin.H{"lastReadMessageId": ""})
		return
	}
	c.JSON(200, gin.H{"lastReadMessageId": rs.LastReadMessageID})
}

type readReq struct {
	MessageID string `json:"messageId"`
}

func (s *Server) PutReadState(c *gin.Context) {
	uid := auth.UserID(c)
	cid := c.Param("id")
	var req readReq
	if err := c.ShouldBindJSON(&req); err != nil || req.MessageID == "" {
		fail(c, 400, "参数错误")
		return
	}
	rs := models.ReadState{UserID: uid, ChannelID: cid, LastReadMessageID: req.MessageID, UpdatedAt: time.Now()}
	s.DB.Where("user_id = ? AND channel_id = ?", uid, cid).Assign(rs).FirstOrCreate(&rs)
	s.DB.Model(&rs).Updates(map[string]any{"last_read_message_id": req.MessageID, "updated_at": time.Now()})
	c.JSON(200, gin.H{"ok": true})
}

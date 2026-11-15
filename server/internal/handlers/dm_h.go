package handlers

import (
	"time"

	"github.com/gin-gonic/gin"

	"chord/server/internal/auth"
	"chord/server/internal/models"
	"chord/server/internal/ws"
)

type dmResult struct {
	ID           string          `json:"id"`
	Users        []models.UserDTO `json:"users"`
	LastMessageID string         `json:"lastMessageId"`
}

// ListDMs 当前用户的私信会话列表（含对端用户与最后一条消息 ID）。
func (s *Server) ListDMs(c *gin.Context) {
	uid := auth.UserID(c)
	var dms []models.DMChannel
	s.DB.Where("user_a_id = ? OR user_b_id = ?", uid, uid).Order("created_at DESC").Find(&dms)

	out := make([]dmResult, 0, len(dms))
	for _, dm := range dms {
		otherID := dm.UserBID
		if uid == dm.UserBID {
			otherID = dm.UserAID
		}
		var other models.User
		if err := s.DB.Where("id = ?", otherID).First(&other).Error; err != nil {
			continue
		}
		var last models.Message
		lastID := ""
		if err := s.DB.Where("channel_id = ?", dm.ID).Order("id DESC").First(&last).Error; err == nil {
			lastID = last.ID
		}
		out = append(out, dmResult{ID: dm.ID, Users: []models.UserDTO{other.DTO()}, LastMessageID: lastID})
	}
	c.JSON(200, out)
}

// OpenDM 打开（或创建）与某用户的私信，双方都会收到 DM_CREATED。
func (s *Server) OpenDM(c *gin.Context) {
	uid := auth.UserID(c)
	otherID := c.Param("userId")
	if otherID == uid {
		fail(c, 400, "不能和自己私信")
		return
	}
	var other models.User
	if err := s.DB.Where("id = ?", otherID).First(&other).Error; err != nil {
		fail(c, 404, "用户不存在")
		return
	}
	a, b := uid, otherID
	if a > b {
		a, b = b, a
	}
	var dm models.DMChannel
	err := s.DB.Where("user_a_id = ? AND user_b_id = ?", a, b).First(&dm).Error
	if err != nil {
		dm = models.DMChannel{ID: models.NewID(), UserAID: a, UserBID: b, CreatedAt: time.Now()}
		if err := s.DB.Create(&dm).Error; err != nil {
			fail(c, 500, "创建失败")
			return
		}
	}
	var me models.User
	s.DB.Where("id = ?", uid).First(&me)
	env := ws.NewEnvelope(ws.EvDMCreated, dmResult{ID: dm.ID, Users: []models.UserDTO{other.DTO(), me.DTO()}})
	s.Hub.Broadcast("user:"+uid, env)
	s.Hub.Broadcast("user:"+otherID, env)
	c.JSON(200, dmResult{ID: dm.ID, Users: []models.UserDTO{other.DTO()}})
}

// Summary 汇总用户所有可见频道的未读情况，用于频道列表徽标。
func (s *Server) Summary(c *gin.Context) {
	uid := auth.UserID(c)

	// 1. 用户可见的频道：所在服务器的频道 + 私信
	guildIDs := s.guildIDsOf(uid)
	var channels []models.Channel
	if len(guildIDs) > 0 {
		s.DB.Where("guild_id IN ?", guildIDs).Find(&channels)
	}
	var dms []models.DMChannel
	s.DB.Where("user_a_id = ? OR user_b_id = ?", uid, uid).Find(&dms)

	type chSummary struct {
		ChannelID     string `json:"channelId"`
		LastMessageID string `json:"lastMessageId"`
		Unread        int64  `json:"unread"`
		Mentions      int64  `json:"mentions"`
	}
	out := []chSummary{}
	if len(channels) == 0 && len(dms) == 0 {
		c.JSON(200, out)
		return
	}
	chIDs := make([]string, 0, len(channels)+len(dms))
	for _, ch := range channels {
		chIDs = append(chIDs, ch.ID)
	}
	for _, dm := range dms {
		chIDs = append(chIDs, dm.ID)
	}

	// 2. 最后一条消息
	type lastRow struct {
		ChannelID string `gorm:"column:channel_id"`
		LastID    string `gorm:"column:last_id"`
	}
	var lasts []lastRow
	s.DB.Model(&models.Message{}).Select("channel_id, MAX(id) AS last_id").
		Where("channel_id IN ?", chIDs).Group("channel_id").Scan(&lasts)

	// 3. 未读与提及数（读状态 LEFT JOIN，无记录视为全新）
	var u models.User
	s.DB.Where("id = ?", uid).First(&u)
	type countRow struct {
		ChannelID string `gorm:"column:channel_id"`
		Count     int64  `gorm:"column:cnt"`
	}
	var unreadRows, mentionRows []countRow
	s.DB.Raw(`
		SELECT m.channel_id AS channel_id, COUNT(*) AS cnt
		FROM messages m
		LEFT JOIN read_states r ON r.user_id = ? AND r.channel_id = m.channel_id
		WHERE m.channel_id IN ? AND m.id > COALESCE(r.last_read_message_id, '')
		GROUP BY m.channel_id`, uid, chIDs).Scan(&unreadRows)
	s.DB.Raw(`
		SELECT m.channel_id AS channel_id, COUNT(*) AS cnt
		FROM messages m
		LEFT JOIN read_states r ON r.user_id = ? AND r.channel_id = m.channel_id
		WHERE m.channel_id IN ? AND m.id > COALESCE(r.last_read_message_id, '')
		  AND m.author_id <> ? AND m.content LIKE ?
		GROUP BY m.channel_id`, uid, chIDs, uid, "%@"+u.Username+"%").Scan(&mentionRows)

	lastMap := map[string]string{}
	for _, r := range lasts {
		lastMap[r.ChannelID] = r.LastID
	}
	unreadMap := map[string]int64{}
	for _, r := range unreadRows {
		unreadMap[r.ChannelID] = r.Count
	}
	mentionMap := map[string]int64{}
	for _, r := range mentionRows {
		mentionMap[r.ChannelID] = r.Count
	}
	for _, cid := range chIDs {
		if lastMap[cid] == "" {
			continue // 没有消息，谈不上未读
		}
		out = append(out, chSummary{
			ChannelID: cid, LastMessageID: lastMap[cid],
			Unread: unreadMap[cid], Mentions: mentionMap[cid],
		})
	}
	c.JSON(200, out)
}

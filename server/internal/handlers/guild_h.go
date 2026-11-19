package handlers

import (
	"log"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"chord/server/internal/auth"
	"chord/server/internal/models"
	"chord/server/internal/util"
	"chord/server/internal/ws"
)

// genUniqueInvite 生成不与现有服务器冲突的邀请码。
func genUniqueInvite(s *Server) string {
	for i := 0; i < 10; i++ {
		code := util.RandomInviteCode()
		var n int64
		s.DB.Model(&models.Guild{}).Where("invite_code = ?", code).Count(&n)
		if n == 0 {
			return code
		}
	}
	return util.RandomInviteCode()
}

func (s *Server) guildIDsOf(userID string) []string {
	var ids []string
	s.DB.Model(&models.GuildMember{}).Where("user_id = ?", userID).Pluck("guild_id", &ids)
	return ids
}

func (s *Server) isMember(userID, guildID string) bool {
	var n int64
	s.DB.Model(&models.GuildMember{}).Where("guild_id = ? AND user_id = ?", guildID, userID).Count(&n)
	return n > 0
}

// ListGuilds 当前用户加入的所有服务器。
func (s *Server) ListGuilds(c *gin.Context) {
	uid := auth.UserID(c)
	var guilds []models.Guild
	s.DB.Joins("JOIN guild_members gm ON gm.guild_id = guilds.id").
		Where("gm.user_id = ?", uid).Order("guilds.created_at").Find(&guilds)
	c.JSON(200, guilds)
}

type createGuildReq struct {
	Name string `json:"name"`
}

// CreateGuild 创建服务器，自动创建默认频道（公告 / general）。
func (s *Server) CreateGuild(c *gin.Context) {
	uid := auth.UserID(c)
	var req createGuildReq
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Name) < 1 || len([]rune(req.Name)) > 32 {
		fail(c, 400, "服务器名称需为 1-32 个字符")
		return
	}
	g := models.Guild{
		ID: models.NewID(), Name: req.Name, OwnerID: uid,
		InviteCode: genUniqueInvite(s),
		IconColor:  avatarColors[len(req.Name)%len(avatarColors)],
	}
	err := s.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&g).Error; err != nil {
			return err
		}
		if err := tx.Create(&models.GuildMember{GuildID: g.ID, UserID: uid, JoinedAt: time.Now()}).Error; err != nil {
			return err
		}
		defaults := []models.Channel{
			{ID: models.NewID(), GuildID: g.ID, Name: "公告", Category: "信息", Position: 0},
			{ID: models.NewID(), GuildID: g.ID, Name: "general", Category: "闲聊", Position: 1},
		}
		return tx.Create(&defaults).Error
	})
	if err != nil {
		log.Printf("[guild] create failed: %v", err)
		fail(c, 500, "创建失败")
		return
	}
	var channels []models.Channel
	s.DB.Where("guild_id = ?", g.ID).Order("position").Find(&channels)
	c.JSON(200, gin.H{"guild": g, "channels": channels})
}

// ListChannels 服务器内频道列表（需为成员）。
func (s *Server) ListChannels(c *gin.Context) {
	uid := auth.UserID(c)
	gid := c.Param("id")
	if !s.isMember(uid, gid) {
		fail(c, 403, "不在该服务器中")
		return
	}
	var channels []models.Channel
	s.DB.Where("guild_id = ?", gid).Order("position, created_at").Find(&channels)
	out := make([]map[string]any, len(channels))
	for i := range channels {
		out[i] = channels[i].DTO()
	}
	c.JSON(200, out)
}

type createChannelReq struct {
	Name      string `json:"name"`
	Category  string `json:"category"`
	OwnerOnly bool   `json:"ownerOnly"` // true = 公告型频道：仅创建者可发言
}

// CreateChannel 创建文字频道。
func (s *Server) CreateChannel(c *gin.Context) {
	uid := auth.UserID(c)
	gid := c.Param("id")
	if !s.isMember(uid, gid) {
		fail(c, 403, "不在该服务器中")
		return
	}
	var req createChannelReq
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Name) < 1 || len([]rune(req.Name)) > 32 {
		fail(c, 400, "频道名称需为 1-32 个字符")
		return
	}
	var maxPos int
	s.DB.Model(&models.Channel{}).Where("guild_id = ?", gid).
		Select("COALESCE(MAX(position),-1)").Scan(&maxPos)
	speakMode := models.SpeakAll
	if req.OwnerOnly {
		speakMode = models.SpeakOwner
	}
	ch := models.Channel{
		ID: models.NewID(), GuildID: gid, Name: req.Name,
		Category: req.Category, Position: maxPos + 1,
		CreatedBy: uid, SpeakMode: speakMode,
	}
	if err := s.DB.Create(&ch).Error; err != nil {
		fail(c, 500, "创建失败")
		return
	}
	s.Hub.Broadcast("guild:"+gid, ws.NewEnvelope(ws.EvChannelCreated, ch.DTO()))
	c.JSON(200, ch.DTO())
}

type updateChannelReq struct {
	Name            *string  `json:"name"`
	Category        *string  `json:"category"`
	SpeakMode       *string  `json:"speakMode"`
	AllowedSpeakers []string `json:"allowedSpeakers"`
}

// UpdateChannel 改名/改分组/改发言权限。仅频道创建者或服务器所有者可改。
func (s *Server) UpdateChannel(c *gin.Context) {
	uid := auth.UserID(c)
	cid := c.Param("id")
	var ch models.Channel
	if err := s.DB.Where("id = ?", cid).First(&ch).Error; err != nil {
		fail(c, 404, "频道不存在")
		return
	}
	var g models.Guild
	if err := s.DB.Where("id = ?", ch.GuildID).First(&g).Error; err != nil {
		fail(c, 404, "服务器不存在")
		return
	}
	if uid != ch.CreatedBy && uid != g.OwnerID {
		fail(c, 403, "只有频道创建者或服务器所有者可以修改频道")
		return
	}
	var req updateChannelReq
	if err := c.ShouldBindJSON(&req); err != nil {
		fail(c, 400, "参数错误")
		return
	}
	updates := map[string]any{}
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" || len([]rune(name)) > 32 {
			fail(c, 400, "频道名称需为 1-32 个字符")
			return
		}
		updates["name"] = name
	}
	if req.Category != nil {
		cat := strings.TrimSpace(*req.Category)
		if len([]rune(cat)) > 32 {
			fail(c, 400, "分组名过长")
			return
		}
		updates["category"] = cat
	}
	if req.SpeakMode != nil {
		switch *req.SpeakMode {
		case models.SpeakAll, models.SpeakOwner, models.SpeakCustom, models.SpeakNone:
			updates["speak_mode"] = *req.SpeakMode
		default:
			fail(c, 400, "无效的发言模式")
			return
		}
	}
	if req.AllowedSpeakers != nil {
		ch.SetAllowedSpeakers(req.AllowedSpeakers)
		updates["allowed_speakers"] = ch.AllowedSpeakers
	}
	if len(updates) == 0 {
		fail(c, 400, "没有需要修改的字段")
		return
	}
	if err := s.DB.Model(&ch).Updates(updates).Error; err != nil {
		fail(c, 500, "修改失败")
		return
	}
	s.DB.Where("id = ?", cid).First(&ch)
	s.Hub.Broadcast("guild:"+ch.GuildID, ws.NewEnvelope(ws.EvChannelUpdate, ch.DTO()))
	c.JSON(200, ch.DTO())
}

// DeleteChannel 删除频道（仅服务器所有者），级联删除消息与回应。
func (s *Server) DeleteChannel(c *gin.Context) {
	uid := auth.UserID(c)
	cid := c.Param("id")
	var ch models.Channel
	if err := s.DB.Where("id = ?", cid).First(&ch).Error; err != nil {
		fail(c, 404, "频道不存在")
		return
	}
	if !s.isMember(uid, ch.GuildID) {
		fail(c, 403, "不在该服务器中")
		return
	}
	var g models.Guild
	s.DB.Where("id = ?", ch.GuildID).First(&g)
	if g.OwnerID != uid {
		fail(c, 403, "仅服务器所有者可删除频道")
		return
	}
	s.DB.Where("channel_id = ?", cid).Delete(&models.Reaction{})
	s.DB.Where("channel_id = ?", cid).Delete(&models.Message{})
	s.DB.Where("channel_id = ?", cid).Delete(&models.ReadState{})
	s.DB.Delete(&ch)
	s.Hub.Broadcast("guild:"+ch.GuildID, ws.NewEnvelope(ws.EvChannelDeleted, map[string]string{
		"channelId": cid, "guildId": ch.GuildID,
	}))
	c.JSON(200, gin.H{"ok": true})
}

type memberResult struct {
	models.UserDTO
	Status string `json:"status"`
}

// ListMembers 服务器成员列表（含在线状态）。
func (s *Server) ListMembers(c *gin.Context) {
	uid := auth.UserID(c)
	gid := c.Param("id")
	if !s.isMember(uid, gid) {
		fail(c, 403, "不在该服务器中")
		return
	}
	var users []models.User
	s.DB.Joins("JOIN guild_members gm ON gm.user_id = users.id").
		Where("gm.guild_id = ?", gid).Order("users.created_at").Find(&users)
	out := make([]memberResult, 0, len(users))
	for _, u := range users {
		out = append(out, memberResult{UserDTO: u.DTO(), Status: s.Hub.PresenceStatus(u.ID)})
	}
	c.JSON(200, out)
}

type leaveReq struct {
	SuccessorID string `json:"successorId"` // 所有者退出时指定的新所有者
}

// LeaveGuild 退出服务器。所有者退出必须同时转让所有权（successorId）。
func (s *Server) LeaveGuild(c *gin.Context) {
	uid := auth.UserID(c)
	gid := c.Param("id")
	var g models.Guild
	if err := s.DB.Where("id = ?", gid).First(&g).Error; err != nil {
		fail(c, 404, "服务器不存在")
		return
	}
	var req leaveReq
	_ = c.ShouldBindJSON(&req) // body 可选

	if g.OwnerID == uid {
		if req.SuccessorID == "" {
			fail(c, 400, "所有者退出前需转让所有权，或解散服务器")
			return
		}
		if !s.isMember(req.SuccessorID, gid) || req.SuccessorID == uid {
			fail(c, 400, "接任者必须是该服务器的其他成员")
			return
		}
		if err := s.DB.Model(&g).Update("owner_id", req.SuccessorID).Error; err != nil {
			fail(c, 500, "转让失败")
			return
		}
	}
	s.DB.Where("guild_id = ? AND user_id = ?", gid, uid).Delete(&models.GuildMember{})
	s.Hub.InvalidateGuild(gid)
	s.Hub.Broadcast("guild:"+gid, ws.NewEnvelope(ws.EvMemberLeft, map[string]string{
		"guildId": gid, "userId": uid,
	}))
	c.JSON(200, gin.H{"ok": true})
}

// TransferGuild 转让服务器所有权（不退出）。
func (s *Server) TransferGuild(c *gin.Context) {
	uid := auth.UserID(c)
	gid := c.Param("id")
	var req leaveReq
	if err := c.ShouldBindJSON(&req); err != nil || req.SuccessorID == "" {
		fail(c, 400, "参数错误")
		return
	}
	var g models.Guild
	if err := s.DB.Where("id = ?", gid).First(&g).Error; err != nil {
		fail(c, 404, "服务器不存在")
		return
	}
	if g.OwnerID != uid {
		fail(c, 403, "仅所有者可转让")
		return
	}
	if !s.isMember(req.SuccessorID, gid) || req.SuccessorID == uid {
		fail(c, 400, "接任者必须是该服务器的其他成员")
		return
	}
	if err := s.DB.Model(&g).Update("owner_id", req.SuccessorID).Error; err != nil {
		fail(c, 500, "转让失败")
		return
	}
	c.JSON(200, gin.H{"ok": true})
}

// DeleteGuild 解散服务器（仅所有者）：级联删除频道、消息、回应、成员等。
func (s *Server) DeleteGuild(c *gin.Context) {
	uid := auth.UserID(c)
	gid := c.Param("id")
	var g models.Guild
	if err := s.DB.Where("id = ?", gid).First(&g).Error; err != nil {
		fail(c, 404, "服务器不存在")
		return
	}
	if g.OwnerID != uid {
		fail(c, 403, "仅所有者可解散服务器")
		return
	}
	// 先通知在线成员（此时成员表还在，受众解析正常）
	s.Hub.Broadcast("guild:"+gid, ws.NewEnvelope(ws.EvGuildDeleted, map[string]string{"guildId": gid}))
	s.Hub.InvalidateGuild(gid)

	var channelIDs []string
	s.DB.Model(&models.Channel{}).Where("guild_id = ?", gid).Pluck("id", &channelIDs)
	if len(channelIDs) > 0 {
		s.DB.Where("channel_id IN ?", channelIDs).Delete(&models.Message{})
		s.DB.Where("channel_id IN ?", channelIDs).Delete(&models.Reaction{})
		s.DB.Where("channel_id IN ?", channelIDs).Delete(&models.ReadState{})
	}
	s.DB.Where("guild_id = ?", gid).Delete(&models.Channel{})
	s.DB.Where("guild_id = ?", gid).Delete(&models.GuildMember{})
	s.DB.Delete(&g)
	c.JSON(200, gin.H{"ok": true})
}

// RegenInvite 重新生成邀请码。
func (s *Server) RegenInvite(c *gin.Context) {
	uid := auth.UserID(c)
	gid := c.Param("id")
	var g models.Guild
	if err := s.DB.Where("id = ?", gid).First(&g).Error; err != nil {
		fail(c, 404, "服务器不存在")
		return
	}
	if g.OwnerID != uid {
		fail(c, 403, "仅服务器所有者可重置邀请码")
		return
	}
	code := genUniqueInvite(s)
	s.DB.Model(&g).Update("invite_code", code)
	c.JSON(200, gin.H{"inviteCode": code})
}

// GuildPreview 邀请码预览（未登录也可看）。
func (s *Server) GuildPreview(c *gin.Context) {
	var g models.Guild
	if err := s.DB.Where("invite_code = ?", c.Param("code")).First(&g).Error; err != nil {
		fail(c, 404, "邀请码无效")
		return
	}
	var n int64
	s.DB.Model(&models.GuildMember{}).Where("guild_id = ?", g.ID).Count(&n)
	c.JSON(200, gin.H{"name": g.Name, "iconColor": g.IconColor, "memberCount": n})
}

// JoinGuild 通过邀请码加入，并向全服广播 MEMBER_JOINED。
func (s *Server) JoinGuild(c *gin.Context) {
	uid := auth.UserID(c)
	var g models.Guild
	if err := s.DB.Where("invite_code = ?", c.Param("code")).First(&g).Error; err != nil {
		fail(c, 404, "邀请码无效")
		return
	}
	if s.isMember(uid, g.ID) {
		fail(c, 409, "已在服务器中")
		return
	}
	if err := s.DB.Create(&models.GuildMember{GuildID: g.ID, UserID: uid, JoinedAt: time.Now()}).Error; err != nil {
		log.Printf("[guild] join failed: %v", err)
		fail(c, 500, "加入失败")
		return
	}
	s.Hub.InvalidateGuild(g.ID)
	var u models.User
	s.DB.Where("id = ?", uid).First(&u)
	s.Hub.Broadcast("guild:"+g.ID, ws.NewEnvelope(ws.EvMemberJoined, map[string]any{
		"guildId": g.ID, "user": u.DTO(),
	}))
	c.JSON(200, gin.H{"guild": g})
}

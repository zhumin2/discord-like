package models

import (
	"time"

	"github.com/google/uuid"
)

// NewID 返回时间有序 UUIDv7，用作主键与消息分页游标。
func NewID() string {
	id, err := uuid.NewV7()
	if err != nil { // 理论上不会发生；兜底随机
		return uuid.NewString()
	}
	return id.String()
}

type User struct {
	ID           string    `gorm:"type:char(36);primaryKey" json:"id"`
	Username     string    `gorm:"size:32;not null;uniqueIndex:idx_user_disc,priority:1" json:"username"`
	Discriminator string   `gorm:"type:char(4);not null;uniqueIndex:idx_user_disc,priority:2" json:"discriminator"`
	PasswordHash string    `gorm:"size:100;not null" json:"-"`
	AvatarColor  string    `gorm:"size:9;not null;default:#5865F2" json:"avatarColor"`
	CreatedAt    time.Time `json:"createdAt"`
}

func (u *User) Tag() string { return u.Username + "#" + u.Discriminator }

// UserDTO 是对外输出的用户公开信息。
type UserDTO struct {
	ID          string `json:"id"`
	Username    string `json:"username"`
	Discriminator string `json:"discriminator"`
	AvatarColor string `json:"avatarColor"`
}

func (u *User) DTO() UserDTO {
	return UserDTO{ID: u.ID, Username: u.Username, Discriminator: u.Discriminator, AvatarColor: u.AvatarColor}
}

type Guild struct {
	ID         string    `gorm:"type:char(36);primaryKey" json:"id"`
	Name       string    `gorm:"size:64;not null" json:"name"`
	OwnerID    string    `gorm:"type:char(36);not null;index" json:"ownerId"`
	InviteCode string    `gorm:"size:16;not null;uniqueIndex" json:"inviteCode"`
	IconColor  string    `gorm:"size:9;not null;default:#5865F2" json:"iconColor"`
	CreatedAt  time.Time `json:"createdAt"`
}

type GuildMember struct {
	GuildID  string    `gorm:"type:char(36);primaryKey;autoIncrement:false"`
	UserID   string    `gorm:"type:char(36);primaryKey;autoIncrement:false"`
	JoinedAt time.Time `json:"joinedAt"`
}

type Channel struct {
	ID        string    `gorm:"type:char(36);primaryKey" json:"id"`
	GuildID   string    `gorm:"type:char(36);not null;index" json:"guildId"`
	Name      string    `gorm:"size:32;not null" json:"name"`
	Category  string    `gorm:"size:32;not null;default:''" json:"category"`
	Position  int       `gorm:"not null;default:0" json:"position"`
	CreatedAt time.Time `json:"createdAt"`
}

// DMChannel 私信会话；UserAID 恒为较小 ID，保证 (a,b) 唯一。
type DMChannel struct {
	ID        string    `gorm:"type:char(36);primaryKey" json:"id"`
	UserAID   string    `gorm:"type:char(36);not null;uniqueIndex:idx_dm_pair,priority:1" json:"-"`
	UserBID   string    `gorm:"type:char(36);not null;uniqueIndex:idx_dm_pair,priority:2" json:"-"`
	CreatedAt time.Time `json:"createdAt"`
}

// Messages.channel_id 不设外键：同时容纳频道消息（channels.id）与私信（dm_channels.id）。
type Message struct {
	ID        string     `gorm:"type:char(36);primaryKey" json:"id"`
	ChannelID string     `gorm:"type:char(36);not null;index:idx_msg_ch_id,priority:1" json:"channelId"`
	AuthorID  string     `gorm:"type:char(36);not null" json:"authorId"`
	Content   string     `gorm:"type:text;not null" json:"content"`
	ReplyToID string     `gorm:"type:char(36);not null;default:''" json:"replyToId"` // 引用回复的消息 ID（空=非回复）
	EditedAt  *time.Time `json:"editedAt"`
	CreatedAt time.Time  `gorm:"index:idx_msg_ch_id,priority:2" json:"createdAt"`

	// 非持久化：JOIN 出的作者信息、回应汇总、被引用消息摘要
	Author            *UserDTO          `gorm:"-" json:"author,omitempty"`
	ReactionSummaries []ReactionSummary `gorm:"-" json:"reactionSummaries"`
	ReplyTo           *ReplyPreview     `gorm:"-" json:"replyTo,omitempty"`
}

// ReactionSummary 是某条消息一个 emoji 的聚合视图。
type ReactionSummary struct {
	Emoji string   `json:"emoji"`
	Count int      `json:"count"`
	Mine  bool     `json:"mine"`
	Users []string `json:"users,omitempty"` // 前 3 个用户 ID，供 tooltip
}

// ReplyPreview 是被引用消息的摘要，供客户端渲染"引用块"。
type ReplyPreview struct {
	ID          string `json:"id"`
	AuthorName  string `json:"authorName"`
	AuthorColor string `json:"authorColor"`
	Content     string `json:"content"` // 已截断为 ~120 字符
}

type Reaction struct {
	ID        string    `gorm:"type:char(36);primaryKey"`
	MessageID string    `gorm:"type:char(36);not null;uniqueIndex:idx_react,priority:1" json:"messageId"`
	UserID    string    `gorm:"type:char(36);not null;uniqueIndex:idx_react,priority:2" json:"userId"`
	Emoji     string    `gorm:"size:32;not null;uniqueIndex:idx_react,priority:3" json:"emoji"`
	CreatedAt time.Time `json:"createdAt"`
}

type ReadState struct {
	UserID            string    `gorm:"type:char(36);primaryKey;autoIncrement:false"`
	ChannelID         string    `gorm:"type:char(36);primaryKey;autoIncrement:false"`
	LastReadMessageID string    `gorm:"type:char(36);not null;default:''"`
	UpdatedAt         time.Time
}

func (ReadState) TableName() string { return "read_states" }

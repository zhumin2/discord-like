package models

import "testing"

func TestCanSpeak(t *testing.T) {
	const owner = "owner"
	const creator = "creator"
	const member = "member"

	all := Channel{SpeakMode: SpeakAll}
	if !all.CanSpeak(member, owner) {
		t.Fatal("all: any member should speak")
	}
	own := Channel{SpeakMode: SpeakOwner, CreatedBy: creator}
	if !own.CanSpeak(creator, owner) || own.CanSpeak(member, owner) {
		t.Fatal("owner-only: only creator (and guild owner) should speak")
	}
	custom := Channel{SpeakMode: SpeakCustom, CreatedBy: creator}
	custom.SetAllowedSpeakers([]string{member})
	if !custom.CanSpeak(member, owner) || !custom.CanSpeak(creator, owner) {
		t.Fatal("custom: creator + allowed members should speak")
	}
	none := Channel{SpeakMode: SpeakNone, CreatedBy: creator}
	// 归档频道：连服务器所有者也不能发言（用户反馈：设为无人后仍能发）
	for _, uid := range []string{member, creator, owner} {
		if none.CanSpeak(uid, owner) {
			t.Fatalf("none: %s must not speak", uid)
		}
	}
}

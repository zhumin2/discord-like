package util

import (
	"crypto/rand"
	"encoding/hex"
	"math/big"
)

// RandomHex 生成 n 字节随机数的十六进制字符串。
func RandomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func randomToken(n int) string { return RandomHex(n) }

const inviteAlphabet = "abcdefghjkmnpqrstuvwxyz23456789"

// RandomInviteCode 生成 8 位易读邀请码（去除易混淆字符）。
func RandomInviteCode() string {
	out := make([]byte, 8)
	for i := range out {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(inviteAlphabet))))
		out[i] = inviteAlphabet[n.Int64()]
	}
	return string(out)
}

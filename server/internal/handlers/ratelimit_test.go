package handlers

import (
	"sync"
	"testing"
	"time"
)

func TestRateLimiterAllowsWithinMax(t *testing.T) {
	l := newRateLimiter(3, time.Second)
	for i := 0; i < 3; i++ {
		if !l.allow("k1") {
			t.Fatalf("第 %d 次请求被拒，应在窗口内放行", i+1)
		}
	}
	if l.allow("k1") {
		t.Fatal("超过 max=3 后应被拒绝")
	}
	// 不同 key 互不影响
	if !l.allow("k2") {
		t.Fatal("不同 key 不应互相影响")
	}
}

func TestRateLimiterWindowReset(t *testing.T) {
	l := newRateLimiter(1, 30*time.Millisecond)
	if !l.allow("k") {
		t.Fatal("首次请求应放行")
	}
	if l.allow("k") {
		t.Fatal("窗口内第二次应被拒")
	}
	time.Sleep(40 * time.Millisecond)
	if !l.allow("k") {
		t.Fatal("窗口过期后应重新放行")
	}
}

func TestRateLimiterConcurrent(t *testing.T) {
	l := newRateLimiter(100, time.Second)
	var mu sync.Mutex
	granted := 0
	var wg sync.WaitGroup
	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if l.allow("c") {
				mu.Lock()
				granted++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if granted != 100 {
		t.Fatalf("并发下应精确放行 100 次，实际 %d", granted)
	}
}

func TestCooldownLimiter(t *testing.T) {
	l := newCooldownLimiter(50 * time.Millisecond)
	if !l.allow("u1") {
		t.Fatal("first send should pass")
	}
	if l.allow("u1") {
		t.Fatal("second immediate send should be blocked")
	}
	if !l.allow("u2") {
		t.Fatal("other user unaffected")
	}
	time.Sleep(60 * time.Millisecond)
	if !l.allow("u1") {
		t.Fatal("send after interval should pass")
	}
}

func TestCooldownDisabled(t *testing.T) {
	l := newCooldownLimiter(0)
	for i := 0; i < 10; i++ {
		if !l.allow("u1") {
			t.Fatal("interval=0 should never block")
		}
	}
}

func TestCooldownBlockedDoesNotConsume(t *testing.T) {
	l := newCooldownLimiter(50 * time.Millisecond)
	if l.blocked("u1") {
		t.Fatal("fresh key must not be blocked")
	}
	// 被拒绝的请求只查询不记录：连续查询多次也不应进入冷却
	for i := 0; i < 5; i++ {
		if l.blocked("u1") {
			t.Fatal("blocked() must not start the cooldown")
		}
	}
	l.mark("u1")
	if !l.blocked("u1") {
		t.Fatal("after mark the key must be blocked")
	}
	time.Sleep(60 * time.Millisecond)
	if l.blocked("u1") {
		t.Fatal("after interval the key must be allowed again")
	}
}

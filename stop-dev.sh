#!/usr/bin/env bash
# 停止 Chord 全部服务（等价于 bash chord.sh stop）
exec bash "$(dirname "$0")/chord.sh" stop "${1:-all}"

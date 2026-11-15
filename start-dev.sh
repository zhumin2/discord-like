#!/usr/bin/env bash
# 一键启动 Chord 全部服务（等价于 bash chord.sh start）
# 更多命令见 chord.sh: stop / restart / status / logs [api|web|mysql]
exec bash "$(dirname "$0")/chord.sh" start "${1:-all}"

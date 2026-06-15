#!/bin/bash
# enjoy3 一键编译 + 重置授权 + 启动
# 用法:
#   ./build.sh              编译 + 重置权限 + 启动
#   ./build.sh --no-reset   编译 + 启动 (不重置权限)
#   ./build.sh --no-open    只编译, 不启动
#   ./build.sh --clean      清理后再编译

set -e  # 任何步骤失败立即退出

# ---------- 配置 ----------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_YML="$PROJECT_DIR/project.yml"
PROJECT="$PROJECT_DIR/enjoy3.xcodeproj"
BUNDLE_ID="net.tunah.enjoy3"
APP_PATH="$PROJECT_DIR/build/Release/enjoy3.app"

# ---------- 颜色输出 ----------
G='\033[0;32m'  # green
Y='\033[1;33m'  # yellow
R='\033[0;31m'  # red
N='\033[0m'     # reset

log()  { printf "${G}[build]${N} %s\n" "$*"; }
warn() { printf "${Y}[build]${N} %s\n" "$*"; }
err()  { printf "${R}[build]${N} %s\n" "$*"; }

# ---------- 参数 ----------
DO_RESET=1
DO_OPEN=1
DO_CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --no-reset) DO_RESET=0 ;;
    --no-open)  DO_OPEN=0 ;;
    --clean)    DO_CLEAN=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) warn "未知参数: $arg" ;;
  esac
done

# ---------- 步骤 1: 关闭正在运行的实例 ----------
if pgrep -x enjoy3 >/dev/null; then
  log "关闭已运行的 enjoy3..."
  pkill -x enjoy3 || true
  sleep 0.5
fi

# ---------- 步骤 2: 清理 (可选) ----------
if [ "$DO_CLEAN" -eq 1 ]; then
  log "清理 build 目录..."
  rm -rf "$PROJECT_DIR/build"
fi

# ---------- 步骤 3: 生成 Xcode 工程 + 编译 ----------
log "生成 Xcode 工程 (xcodegen)..."
cd "$PROJECT_DIR"
xcodegen generate 2>&1 | tail -5

log "编译 (arm64 Release)..."
xcodebuild \
  -project "$PROJECT" \
  -configuration Release \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build 2>&1 | tail -20

if [ ! -d "$APP_PATH" ]; then
  err "编译失败: 找不到 $APP_PATH"
  exit 1
fi

log "编译成功: $APP_PATH"

# ---------- 步骤 4: 重置辅助功能授权 ----------
if [ "$DO_RESET" -eq 1 ]; then
  log "重置辅助功能权限 ($BUNDLE_ID)..."
  tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || warn "tccutil 重置失败 (可能首次运行,忽略)"
fi

# ---------- 步骤 5: 启动 ----------
if [ "$DO_OPEN" -eq 1 ]; then
  log "启动 enjoy3..."
  open "$APP_PATH"
  warn "如果弹出辅助功能授权请求,请勾选 enjoy3 并启用"
fi

log "完成"

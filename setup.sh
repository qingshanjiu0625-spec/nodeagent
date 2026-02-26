#!/usr/bin/env bash
set -euo pipefail

############################################
# 0) 你指定必须包含的命令（保留原样）
# docker pull qingshanjiu/nodeagent:latest
############################################
# 注意：这条通常用于安装 Homebrew 相关的 openclaw 脚本；Docker 部署不一定需要它。
#/bin/bash -c "$(curl -fsSL https://raw.xxxx.com/Homebrew/install/HEAD/openclaw.sh)" || true

############################################
# 1) 工具函数
############################################
log()  { printf "\033[1;32m[openclaw]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[error]\033[0m %s\n" "$*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

############################################
# 2) 选择 Docker 平台（满足 3：x86/amd64/arm/armv8）
############################################
# 映射规则（常见）：
# - x86_64/amd64 -> linux/amd64
# - i386/i686/x86 -> linux/386
# - armv7l/arm -> linux/arm/v7
# - aarch64/arm64/armv8 -> linux/arm64
platform="linux/amd64"
case "$arch" in
  x86_64|amd64) platform="linux/amd64" ;;
  aarch64|arm64|armv8*) platform="linux/arm64" ;;
  *)
    warn "未识别架构：$arch，默认使用 linux/amd64（如拉取失败请手动改 platform）"
    platform="linux/amd64"
    ;;
esac
log "OS=$os  ARCH=$arch  ->  DOCKER_PLATFORM=$platform"

############################################
# 3) 检查 Docker 环境（满足 1）
############################################
install_docker_linux() {
  log "检测到 Linux：将尝试安装 Docker（需要 sudo 权限）"
  if ! need_cmd curl; then
    sudo apt-get update -y || true
    sudo apt-get install -y curl || true
  fi
  # 官方便捷安装脚本（Docker Engine）
  curl -fsSL https://get.docker.com | sudo sh

  # 启动服务
  sudo systemctl enable docker >/dev/null 2>&1 || true
  sudo systemctl restart docker >/dev/null 2>&1 || true

  # 免 sudo（可选）
  if need_cmd id && need_cmd getent; then
    if ! groups "$USER" | grep -q '\bdocker\b'; then
      sudo usermod -aG docker "$USER" || true
      warn "已把 $USER 加入 docker 组；你可能需要重新登录一次终端让权限生效。"
    fi
  fi
}

if ! need_cmd docker; then
  # 2) 没有 docker 给安装上（满足 2）
  case "$os" in
    linux)
      install_docker_linux
      ;;
    darwin)
      die "macOS 未检测到 docker。请先安装 Docker Desktop，然后重新运行本脚本。"
      ;;
    *)
      die "未检测到 docker，且当前 OS=$os 不在自动安装范围。请先安装 Docker + Compose v2。"
      ;;
  esac
fi

# Compose v2 检测：docker compose ...
if ! docker compose version >/dev/null 2>&1; then
  die "检测不到 Docker Compose v2（docker compose）。请升级 Docker/Compose 后再运行。"
fi

log "Docker OK: $(docker --version)"
log "Compose OK: $(docker compose version | head -n1)"

############################################
# 4) 端口选择（满足 6：默认 62430）
############################################
default_port="62430"
read -r -p "请选择宿主机端口（直接回车默认 ${default_port}）： " host_port
host_port="${host_port:-$default_port}"
if ! [[ "$host_port" =~ ^[0-9]+$ ]] || [ "$host_port" -lt 1 ] || [ "$host_port" -gt 65535 ]; then
  die "端口不合法：$host_port"
fi

############################################
# 4.1) OPENCLAW_GATEWAY_TOKEN（满足 65位）
############################################
OPENCLAW_GATEWAY_TOKEN="$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_lowercase + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(65)))
PY
)"
echo $OPENCLAW_GATEWAY_TOKEN

############################################
# 4.2) 模型选择（支持：NEXOS, Anthropic，OpenAI，Gemini，AI）
# ANTHROPIC_API_KEY：您的 Anthropic API 密钥，用于 Claude 集成（可选）
# OPENAI_API_KEY：您的 OpenAI API 密钥，用于 AI 集成（可选）
# GEMINI_API_KEY： 您的 Gemini API 密钥，用于 AI 集成（可选）
# XAI_API_KEY：用于 AI 集成的 XAI API 密钥（可选
############################################
echo "请选择模型："
echo "1) NEXOS"
echo "2) Anthropic"
echo "3) OpenAI"
echo "4) Gemini"
echo "5) AI (XAI)"

read -p "输入对应数字: " choice

case $choice in
    1)
        read -p "请输入 NEXOS_API_KEY: " key
        API_KEY_KEY="NEXOS_API_KEY"
        API_KEY_VAL="$key"
        ;;
    2)
        read -p "请输入 ANTHROPIC_API_KEY: " key
        API_KEY_KEY="ANTHROPIC_API_KEY"
        API_KEY_VAL="$key"
        ;;
    3)
        read -p "请输入 OPENAI_API_KEY: " key
        API_KEY_KEY="OPENAI_API_KEY"
        API_KEY_VAL="$key"
        ;;
    4)
        read -p "请输入 GEMINI_API_KEY: " key
        API_KEY_KEY="GEMINI_API_KEY"
        API_KEY_VAL="$key"
        ;;
    5)
        read -p "请输入 XAI_API_KEY: " key
        API_KEY_KEY="XAI_API_KEY"
        API_KEY_VAL="$key"
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

############################################
# 5) /data 持久化映射（满足 6.1）
############################################
# 你要求“将 /data 目录给用户映射好”，这里直接用宿主机 /data/openclaw 持久化：
DATA_ROOT="./openclaw"
CONFIG_DIR="${DATA_ROOT}/config"       # -> /home/node/.openclaw
WORKSPACE_DIR="${DATA_ROOT}/workspace" # -> /home/node/.openclaw/workspace
APP_DIR="${DATA_ROOT}/compose"         # docker-compose.yml/.env 放这里

ensure_dir() {
  local d="$1"
  if [ -d "$d" ]; then return 0; fi
  if mkdir -p "$d" 2>/dev/null; then return 0; fi
  warn "创建目录失败（可能无权限）：$d，尝试 sudo..."
  sudo mkdir -p "$d"
  sudo chown -R "$(id -u)":"$(id -g)" "$DATA_ROOT" || true
}
ensure_dir "$CONFIG_DIR"
ensure_dir "$WORKSPACE_DIR"
ensure_dir "$APP_DIR"

log "数据将持久化到："
log "  CONFIG    : $CONFIG_DIR"
log "  WORKSPACE : $WORKSPACE_DIR"
log "  COMPOSE   : $APP_DIR"

############################################
# 6) 选择镜像并按平台拉取（满足 3）
############################################
# 官方 compose 默认用 OPENCLAW_IMAGE（默认 openclaw:local），这里用社区预构建镜像更省事
# 你也可以改成自己 build 的 openclaw:local。
IMAGE_DEFAULT="qingshanjiu/nodeagent:latest"
#read -r -p "请输入要使用的 OpenClaw 镜像（回车默认 ${IMAGE_DEFAULT}）： " OPENCLAW_IMAGE
#OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-$IMAGE_DEFAULT}"
OPENCLAW_IMAGE="$IMAGE_DEFAULT"

log "拉取镜像：${OPENCLAW_IMAGE}（platform=${platform}）"
docker pull --platform "$platform" "$OPENCLAW_IMAGE"

############################################
# 7) 拉取官方 docker-compose.yml（并写入 .env）
############################################
COMPOSE_YML="${APP_DIR}/docker-compose.yml"
ENV_FILE="${APP_DIR}/.env"

log "下载官方 docker-compose.yml 到：$COMPOSE_YML"
curl -fsSL \
  https://raw.githubusercontent.com/openclaw/openclaw/main/docker-compose.yml \
  -o "$COMPOSE_YML"

log "写入 .env 到：$ENV_FILE"
cat >"$ENV_FILE" <<EOF
# OpenClaw Docker env
OPENCLAW_IMAGE=${OPENCLAW_IMAGE}

# 持久化目录（宿主机）
OPENCLAW_CONFIG_DIR=${CONFIG_DIR}
OPENCLAW_WORKSPACE_DIR=${WORKSPACE_DIR}

# 端口：宿主机端口 -> 容器内 18789
OPENCLAW_GATEWAY_PORT=${host_port}

# 可选：绑定方式（lan/loopback），默认 lan
OPENCLAW_GATEWAY_BIND=lan
EOF

############################################
# 8) 生成 gateway token（满足 4.1）
############################################
# 官方 doctor 支持 --generate-gateway-token（可用于自动化）:contentReference[oaicite:1]{index=1}
log "生成/确保 gateway token 存在（写入配置目录内 openclaw.json）"
docker run --rm --platform "$platform" \
  -e "TZ=Asia/Kuala_Lumpur" \
  -e PORT="${host_port}" \
  -e HOME=/home/node \
  -e TERM=xterm-256color \
  -e OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN}" \
  -e "${API_KEY_KEY}=${API_KEY_VAL}" \
  -v "${CONFIG_DIR}:/home/node/.openclaw" \
  -v "${WORKSPACE_DIR}:/home/node/.openclaw/workspace" \
  -p "${host_port}":"${host_port}" \
  "$OPENCLAW_IMAGE" >/dev/null

# 从配置里读出 token（尽量不依赖 jq）
OPENCLAW_JSON="${CONFIG_DIR}/openclaw.json"
if [ ! -f "$OPENCLAW_JSON" ]; then
  warn "未找到 ${OPENCLAW_JSON}，将继续启动，但你可能需要手动在 UI 里设置 token。"
  OPENCLAW_GATEWAY_TOKEN=""
else
  OPENCLAW_GATEWAY_TOKEN="$(python3 - <<'PY'
import json,sys,os
p=os.environ.get("P","")
try:
  d=json.load(open(p,"r",encoding="utf-8"))
  print(((d.get("gateway") or {}).get("auth") or {}).get("token") or "")
except Exception:
  print("")
PY
  P="$OPENCLAW_JSON")"
fi

if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  # 让 compose 环境变量拿到 token（compose 文件会注入 OPENCLAW_GATEWAY_TOKEN）:contentReference[oaicite:2]{index=2}
  # 追加到 .env（覆盖写法：先过滤旧行再追加）
  tmp_env="$(mktemp)"
  grep -v '^OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" >"$tmp_env" || true
  printf "OPENCLAW_GATEWAY_TOKEN=%s\n" "$OPENCLAW_GATEWAY_TOKEN" >>"$tmp_env"
  mv "$tmp_env" "$ENV_FILE"
  log "Gateway token 已生成并写入 .env"
else
  warn "未能自动读出 gateway token。后续你可用命令输出带 token 的 dashboard 链接：docker compose run --rm openclaw-cli dashboard --no-open"
fi

############################################
# 9) 提示用户获取 AI Key（满足 5）
############################################
cat <<'TXT'

================= AI Key 提示 =================
接下来你需要准备你的 AI Provider Key（例如 OpenAI API Key）。
- 建议：先去对应平台创建/复制 Key，再回来粘贴。
- 你也可以先跳过，之后再写入 /data/openclaw/compose/.env 或 OpenClaw 配置中。

TXT

read -r -p "是否现在写入 OPENAI_API_KEY 到 .env？(y/N): " set_key
set_key="${set_key:-N}"
if [[ "$set_key" =~ ^[Yy]$ ]]; then
  read -r -s -p "请输入 OPENAI_API_KEY（输入时不回显）： " OPENAI_API_KEY
  echo
  tmp_env="$(mktemp)"
  grep -v '^OPENAI_API_KEY=' "$ENV_FILE" >"$tmp_env" || true
  printf "OPENAI_API_KEY=%s\n" "$OPENAI_API_KEY" >>"$tmp_env"
  mv "$tmp_env" "$ENV_FILE"
  log "已写入 OPENAI_API_KEY 到 .env"
else
  warn "已跳过写入 AI Key。"
fi

############################################
# 10) 提示用户生成 bot token（满足 4.0）并可选写入渠道（满足 4）
############################################
cat <<'TXT'

================= Bot Token 提示 =================
如果你要接入 Telegram / Discord 等，需要先去平台创建 Bot 并拿到 token。
- Telegram：找 @BotFather 创建 bot，拿到 token
- Discord：Developer Portal 创建应用 -> Bot -> Token

脚本可选帮你执行 channels add（会把 token 写进持久化配置里）
TXT

read -r -p "是否现在配置一个渠道（telegram/discord）？(y/N): " add_channel
add_channel="${add_channel:-N}"
if [[ "$add_channel" =~ ^[Yy]$ ]]; then
  read -r -p "选择渠道类型（telegram/discord）： " channel_type
  channel_type="$(echo "$channel_type" | tr '[:upper:]' '[:lower:]')"
  if [[ "$channel_type" != "telegram" && "$channel_type" != "discord" ]]; then
    warn "未知渠道：$channel_type，跳过配置。"
  else
    read -r -s -p "请输入 ${channel_type} bot token（不回显）： " BOT_TOKEN
    echo
    log "写入渠道配置（docker compose run --rm openclaw-cli channels add ...）"
    (cd "$APP_DIR" && docker compose run --rm openclaw-cli \
      channels add --channel "$channel_type" --token "$BOT_TOKEN")
    log "渠道已配置完成"
  fi
fi

############################################
# 11) 启动 openclaw（满足 7）
############################################
log "启动 OpenClaw Gateway（docker compose up -d openclaw-gateway）"
(cd "$APP_DIR" && docker compose up -d openclaw-gateway)

############################################
# 12) 自动打开浏览器 + 提示 gateway token 登录（满足 8）
############################################
# 官方推荐：dashboard --no-open 重新生成带 token 的仪表板链接:contentReference[oaicite:3]{index=3}
log "获取 dashboard 链接（带 token），并尝试自动打开浏览器"
dash_url="$(
  cd "$APP_DIR" && docker compose run --rm openclaw-cli dashboard --no-open 2>/dev/null \
    | awk 'match($0, /https?:\/\/[^ ]+/, a){print a[0]; exit} match($0, /http:\/\/[^ ]+/, a){print a[0]; exit} { }'
)"

# 如果没抓到链接，就用本地端口兜底
if [ -z "${dash_url:-}" ]; then
  dash_url="http://127.0.0.1:${host_port}/"
fi

log "Dashboard: $dash_url"
case "$os" in
  darwin)  open "$dash_url" >/dev/null 2>&1 || true ;;
  linux)   xdg-open "$dash_url" >/dev/null 2>&1 || true ;;
  *)       true ;;
esac

cat <<TXT

================= 登录提示 =================
浏览器已打开（或请手动打开）：
  $dash_url

如果页面提示 unauthorized / pairing required：
- 你可以再次运行：
  cd "$APP_DIR" && docker compose run --rm openclaw-cli dashboard --no-open

然后用页面设置里粘贴 gateway token（或直接用带 token 的 URL 打开）。
TXT

############################################
# 13) 生成快捷方式（满足 9）
############################################
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

cat >"${BIN_DIR}/openclaw-enter" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${APP_DIR}"
docker compose exec openclaw-gateway bash
EOF

cat >"${BIN_DIR}/openclaw-restart" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${APP_DIR}"
docker compose restart openclaw-gateway
EOF

cat >"${BIN_DIR}/openclaw-logs" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${APP_DIR}"
docker compose logs -f --tail=200 openclaw-gateway
EOF

cat >"${BIN_DIR}/openclaw-dashboard" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${APP_DIR}"
docker compose run --rm openclaw-cli dashboard --no-open
EOF

chmod +x "${BIN_DIR}/openclaw-enter" "${BIN_DIR}/openclaw-restart" "${BIN_DIR}/openclaw-logs" "${BIN_DIR}/openclaw-dashboard"

cat <<TXT

================= 快捷方式已生成 =================
已创建：
  ${BIN_DIR}/openclaw-enter     # 进入容器
  ${BIN_DIR}/openclaw-restart   # 重启 gateway
  ${BIN_DIR}/openclaw-logs      # 看日志
  ${BIN_DIR}/openclaw-dashboard # 输出带 token 的 dashboard 链接

如果你的 PATH 里没有 ~/.local/bin，请追加：
  echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc
  source ~/.bashrc

安装/数据持久化目录：
  ${DATA_ROOT}

完成 ✅
TXT

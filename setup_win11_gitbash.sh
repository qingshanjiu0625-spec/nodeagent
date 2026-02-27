#!/usr/bin/env bash
#set -euo pipefail

############################################
# NodeAgent/OpenClaw 一键部署脚本（Docker run 版）
# - 检查/安装 Docker（Linux）
# - 按架构拉取镜像
# - 生成 gateway token
# - 提示/写入 AI Key、Telegram Bot Token
# - 映射 /data（持久化到 ~/.nodeagent）
# - 启动容器
# - 循环 5 次检查服务就绪（每次 3s），就绪后自动打开浏览器并提示用 token 登录
# - 生成快捷命令：nodeagent {start|stop|restart|enter|logs|uninstall}
############################################

############################################
# 0) 你指定必须包含的命令（保留原样）
############################################
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/qingshanjiu0625-spec/nodeagent/refs/heads/main/setup.sh)" || true

############################################
# 1) 工具函数
############################################
log()  { printf "\033[1;32m[nodeagent]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[error]\033[0m %s\n" "$*"; exit 1; }
need_cmd(){ command -v "$1" >/dev/null 2>&1; }

############################################
# 2) 基础变量（可通过环境变量覆盖）
############################################
CONTAINER_NAME="${CONTAINER_NAME:-nodeagent}"
IMAGE_DEFAULT="${IMAGE_DEFAULT:-docker.io/qingshanjiu/nodeagent:latest}"

DATA_ROOT="${DATA_ROOT:-${HOME}/.nodeagent}"     # 宿主机持久化根目录
APP_DIR="${APP_DIR:-${DATA_ROOT}/compose}"       # 保留给你放配置（不依赖 compose）
CONFIG_DIR="${CONFIG_DIR:-${DATA_ROOT}/config}"
WORKSPACE_DIR="${WORKSPACE_DIR:-${DATA_ROOT}/workspace}"

DEFAULT_PORT="${DEFAULT_PORT:-62430}"

MAX_RETRY="${MAX_RETRY:-10}"
SLEEP_SEC="${SLEEP_SEC:-5}"

############################################
# 3) 安装/卸载辅助
############################################
container_exists() {
  docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"
}

uninstall_container() {
  local remove_data="${1:-0}"   # 1=删除 DATA_ROOT
  local remove_image="${2:-0}"  # 1=删除镜像

  if ! need_cmd docker; then
    die "未检测到 docker，无法卸载。"
  fi

  if container_exists; then
    warn "正在卸载容器：$CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    log "容器已删除：$CONTAINER_NAME"
  else
    warn "容器不存在：$CONTAINER_NAME（无需卸载）"
  fi

  if [ "$remove_image" = "1" ]; then
    warn "正在删除镜像：$OPENCLAW_IMAGE"
    docker rmi -f "$OPENCLAW_IMAGE" >/dev/null 2>&1 || true
  fi

  if [ "$remove_data" = "1" ]; then
    warn "正在删除数据目录（危险操作）：$DATA_ROOT"
    rm -rf "$DATA_ROOT" || true
  fi

  log "卸载完成 ✅"
}

usage() {
  cat <<'TXT'
用法：
  ./setup.sh                # 安装/启动
  ./setup.sh uninstall       # 卸载容器
  ./setup.sh uninstall --data   # 卸载容器 + 删除数据目录（危险）
  ./setup.sh uninstall --image  # 卸载容器 + 删除镜像
TXT
}

############################################
# 4) 处理命令参数：uninstall
############################################
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

# 默认镜像名（uninstall 用得上）
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-$IMAGE_DEFAULT}"

if [ "${1:-}" = "uninstall" ]; then
  remove_data=0
  remove_image=0
  shift || true
  for arg in "$@"; do
    case "$arg" in
      --data)  remove_data=1 ;;
      --image) remove_image=1 ;;
      *) ;;
    esac
  done
  uninstall_container "$remove_data" "$remove_image"
  exit 0
fi

############################################
# 5) OS / 架构 -> Docker platform
############################################
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

platform="linux/amd64"
case "$arch" in
  x86_64|amd64) platform="linux/amd64" ;;
  aarch64|arm64|armv8*) platform="linux/arm64" ;;
  armv7l|armv7|armhf|arm) platform="linux/arm/v7" ;;
  *)
    warn "未识别架构：$arch，默认使用 linux/amd64"
    platform="linux/amd64"
    ;;
esac
log "OS=$os ARCH=$arch -> DOCKER_PLATFORM=$platform"

############################################
# 6) 检查 Docker 环境（Linux 自动安装）
############################################
install_docker_linux() {
  log "检测到 Linux：将尝试安装 Docker（需要 sudo 权限）"
  if ! need_cmd curl; then
    sudo apt-get update -y || true
    sudo apt-get install -y curl || true
  fi
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable docker >/dev/null 2>&1 || true
  sudo systemctl restart docker >/dev/null 2>&1 || true

  if need_cmd id; then
    if ! groups "$USER" 2>/dev/null | grep -q '\bdocker\b'; then
      sudo usermod -aG docker "$USER" || true
      warn "已把 $USER 加入 docker 组；可能需要重新登录终端让权限生效。"
    fi
  fi
}

if ! need_cmd docker; then
  case "$os" in
    linux) install_docker_linux ;;
    darwin) die "macOS 未检测到 docker。请先安装 Docker Desktop 后重试。" ;;
    *) die "未检测到 docker，请先手动安装 Docker 后重试。" ;;
  esac
fi

log "Docker: $(docker --version)"

############################################
# 7) 重复安装判断：容器已存在则不安装
############################################
if container_exists; then
  warn "检测到容器已存在：${CONTAINER_NAME}（视为已安装），将不会重复安装。"
  echo "你可以使用快捷命令："
  echo "  ${CONTAINER_NAME} enter"
  echo "  ${CONTAINER_NAME} restart"
  echo "  ${CONTAINER_NAME} logs"
  echo "如需卸载："
  echo "  ./setup.sh uninstall"
  exit 0
fi

############################################
# 8) 端口选择（默认 62430）
############################################
read -r -p "请选择宿主机端口（直接回车默认 ${DEFAULT_PORT}）： " host_port
host_port="${host_port:-$DEFAULT_PORT}"
if ! [[ "$host_port" =~ ^[0-9]+$ ]] || [ "$host_port" -lt 1 ] || [ "$host_port" -gt 65535 ]; then
  die "端口不合法：$host_port"
fi

############################################
# 9) 生成 gateway token（65位）
############################################
gen_token_65() {
  # 生成 65 位 [a-z0-9]，优先使用 Windows 也常见的工具，避免硬依赖 python3
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 128 | tr -dc 'a-z0-9' | head -c 65
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    node -e "const crypto=require('crypto');const a='abcdefghijklmnopqrstuvwxyz0123456789';let o='';const b=crypto.randomBytes(256);for(let i=0;i<b.length&&o.length<65;i++)o+=a[b[i]%a.length];console.log(o);"
    return 0
  fi
  # Git Bash / Win11 默认有 powershell；优先用 pwsh（PowerShell 7）否则 powershell（Windows PowerShell）
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command "$a='abcdefghijklmnopqrstuvwxyz0123456789';$o='';1..65|%{$o+=$a[(Get-Random -Minimum 0 -Maximum $a.Length)]};$o"
    return 0
  fi
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command "$a='abcdefghijklmnopqrstuvwxyz0123456789';$o='';1..65|%{$o+=$a[(Get-Random -Minimum 0 -Maximum $a.Length)]};$o"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import secrets,string;alphabet=string.ascii_lowercase+string.digits;print(''.join(secrets.choice(alphabet) for _ in range(65)))"
    return 0
  fi
  echo "ERROR: 无法生成 token（缺少 openssl/node/pwsh/powershell/python3）" >&2
  return 1
}

OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(gen_token_65)}"
log "Gateway token（登录用）：$OPENCLAW_GATEWAY_TOKEN"

############################################
# 10) 模型/AI Key 选择与输入
############################################
cat <<'TXT'

================= AI Key 提示 =================
请选择模型并输入对应的 API KEY：
  1) NEXOS
  2) Anthropic (Claude)
  3) OpenAI
  4) Gemini
TXT

echo "请选择模型:"
echo "1) NEXOS"
echo "2) Anthropic"
echo "3) OpenAI"
echo "4) Gemini"

read -r -p "输入对应数字: " choice

API_KEY_KEY=""
API_KEY_VAL=""

case "${choice:-}" in
  1) read -r -p "请输入 NEXOS_API_KEY: " key; API_KEY_KEY="NEXOS_API_KEY"; API_KEY_VAL="$key" ;;
  2) read -r -p "请输入 ANTHROPIC_API_KEY: " key; API_KEY_KEY="ANTHROPIC_API_KEY"; API_KEY_VAL="$key" ;;
  3) read -r -p "请输入 OPENAI_API_KEY: " key; API_KEY_KEY="OPENAI_API_KEY"; API_KEY_VAL="$key" ;;
  4) read -r -p "请输入 GEMINI_API_KEY: " key; API_KEY_KEY="GEMINI_API_KEY"; API_KEY_VAL="$key" ;;
  5) read -r -p "请输入 XAI_API_KEY: " key; API_KEY_KEY="XAI_API_KEY"; API_KEY_VAL="$key" ;;
  *) die "无效选择" ;;
esac

if [ -z "${API_KEY_VAL:-}" ]; then
  die "${API_KEY_KEY} 不能为空"
fi

############################################
# 11) Bot Token（Telegram）
############################################
cat <<'TXT'

================= Bot Token 提示 =================
请输入 Telegram Bot Token（找 @BotFather 创建 bot 获取）。
TXT

read -r -p "请输入 TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  die "Telegram Token 不能为空"
fi

############################################
# 12) 持久化目录（映射到容器 /data）
############################################
ensure_dir() {
  local d="$1"
  if [ -d "$d" ]; then return 0; fi
  if mkdir -p "$d" 2>/dev/null; then return 0; fi
  warn "创建目录失败（可能无权限）：$d，尝试 sudo..."
  sudo mkdir -p "$d"
  sudo chown -R "$(id -u)":"$(id -g)" "$DATA_ROOT" || true
}
ensure_dir "$DATA_ROOT"
ensure_dir "$APP_DIR"
ensure_dir "$CONFIG_DIR"
ensure_dir "$WORKSPACE_DIR"

log "数据持久化目录：${DATA_ROOT}（已映射到容器 /data，防止配置丢失）"

############################################
# 13) 拉取镜像
############################################
log "拉取镜像：${OPENCLAW_IMAGE}（platform=${platform}）"
docker pull --platform "$platform" "$OPENCLAW_IMAGE"

############################################
# 14) 启动容器（docker run）
############################################
log "启动容器：${CONTAINER_NAME}"
volume_arg="-v ${DATA_ROOT}:/data"
# Windows / macOS / Docker Desktop 不需要（也可能不支持）SELinux 的 :Z 参数，仅 Linux 才加
if [[ "$os" == linux* ]]; then
  volume_arg="-v ${DATA_ROOT}:/data:Z"
fi

docker run -d --name "${CONTAINER_NAME}" --restart=always \
  -e "PORT=${host_port}" \
  -e "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}" \
  -e "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}" \
  -e "${API_KEY_KEY}=${API_KEY_VAL}" \
  ${volume_arg} \
  -p "${host_port}:${host_port}" \
  "${OPENCLAW_IMAGE}"

############################################
# 15) 循环检查服务是否就绪（5次，每次 3 秒）
############################################
http_ready() {
  if need_cmd curl; then
    curl -fsS --max-time 2 "http://127.0.0.1:${host_port}/" >/dev/null 2>&1
    return $?
  fi
  if need_cmd nc; then
    nc -z 127.0.0.1 "$host_port" >/dev/null 2>&1
    return $?
  fi
  (echo >/dev/tcp/127.0.0.1/"$host_port") >/dev/null 2>&1
}

is_ready() {
  local status
  status="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  [ "$status" = "running" ] || return 1
  http_ready
}

log "等待服务就绪（最多 ${MAX_RETRY} 次，每次间隔 ${SLEEP_SEC}s）..."
ready=0
for ((i=1; i<=MAX_RETRY; i++)); do
  if is_ready; then
    ready=1
    log "服务已就绪 ✅（第 ${i} 次检测成功）"
    break
  fi
  if [ "$i" -lt "$MAX_RETRY" ]; then
    warn "第 ${i} 次检测失败，${SLEEP_SEC}s 后重试..."
    sleep "$SLEEP_SEC"
  fi
done

if [ "$ready" -ne 1 ]; then
  warn "服务未在规定次数内就绪，请查看日志："
  echo "  docker logs -f --tail=200 ${CONTAINER_NAME}"
  exit 1
fi

############################################
# 16) 自动打开浏览器 + 提示使用 gateway token 登录
############################################
DASH_URL="http://127.0.0.1:${host_port}/?token=${OPENCLAW_GATEWAY_TOKEN}"

open_browser() {
  case "$(uname -s)" in
    Darwin)
      open "$DASH_URL" >/dev/null 2>&1 || true
      ;;
    Linux)
      if need_cmd xdg-open; then
        xdg-open "$DASH_URL" >/dev/null 2>&1 || true
      else
        warn "找不到 xdg-open，无法自动打开浏览器，请手动打开：$DASH_URL"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Windows Git Bash / MSYS2 / Cygwin
      if need_cmd cmd.exe; then
        cmd.exe /c start "" "$DASH_URL" >/dev/null 2>&1 || true
      elif need_cmd powershell; then
        powershell -NoProfile -Command "Start-Process '$DASH_URL'" >/dev/null 2>&1 || true
      else
        warn "无法自动打开浏览器，请手动打开：$DASH_URL"
      fi
      ;;
    *)
      warn "未知系统，无法自动打开浏览器，请手动打开：$DASH_URL"
      ;;
  esac
}

log "正在打开浏览器：$DASH_URL"
open_browser

cat <<TXT

================= 登录提示 =================
浏览器已打开（或请手动打开）：
  $DASH_URL

请使用 gateway token 登录/配对：
  $OPENCLAW_GATEWAY_TOKEN

查看日志：
  docker logs -f --tail=200 $CONTAINER_NAME

卸载：
  ./setup.sh uninstall
TXT

############################################
# 17) 生成快捷方式：~/.local/bin/nodeagent
############################################
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"

cat >"${BIN_DIR}/nodeagent" <<EOF
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker 未安装"
  exit 1
fi

case "\${1:-}" in
  start)   docker start "\$CONTAINER_NAME" ;;
  stop)    docker stop "\$CONTAINER_NAME" ;;
  restart) docker restart "\$CONTAINER_NAME" ;;
  enter)   docker exec -it "\$CONTAINER_NAME" bash ;;
  logs)    docker logs -f --tail=200 "\$CONTAINER_NAME" ;;
  uninstall)
    docker stop "\$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "\$CONTAINER_NAME" >/dev/null 2>&1 || true
    echo "已卸载容器：\$CONTAINER_NAME"
    echo "如需删除数据目录（危险）：rm -rf \"${DATA_ROOT}\""
    ;;
  *)
    echo "Usage: nodeagent {start|stop|restart|enter|logs|uninstall}"
    ;;
esac
EOF

chmod +x "${BIN_DIR}/nodeagent"

############################################
# 生成 openclaw 别名命令
############################################

cat > "${BIN_DIR}/openclaw" <<EOF
#!/usr/bin/env bash

CONTAINER_NAME="${CONTAINER_NAME}"

if ! docker ps --format '{{.Names}}' | grep -qx "\$CONTAINER_NAME"; then
  echo "容器未运行：\$CONTAINER_NAME"
  echo "请先执行：nodeagent start"
  exit 1
fi

if [ "\$1" = "gateway" ]; then
  shift
  case "\$1" in
    start|stop|restart|status)
      docker exec "\$CONTAINER_NAME" openclaw gateway "\$1"
      ;;
    *)
      echo "Usage: openclaw gateway {start|stop|restart|status}"
      ;;
  esac
else
  echo "Usage:"
  echo "  openclaw gateway {start|stop|restart|status}"
fi
EOF

chmod +x "${BIN_DIR}/openclaw"

cat <<TXT

================= 快捷方式已生成 =================
已创建：
  nodeagent enter       # 进入容器
  nodeagent restart     # 重启容器
  nodeagent start       # 启动容器
  nodeagent stop        # 停止容器
  nodeagent logs        # 查看日志
  nodeagent uninstall   # 卸载容器（不删数据）

openclaw 相关快捷方式：
  openclaw gateway start
  openclaw gateway stop
  openclaw gateway restart
  openclaw gateway status

如果你的 PATH 里没有 ~/.local/bin，使用 快捷方式 请追加：
  echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc
  source ~/.bashrc

数据持久化目录：
  ${DATA_ROOT}

完成 ✅
TXT
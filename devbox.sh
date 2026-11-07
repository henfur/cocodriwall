# devbox launcher. Nix prepends the DEVBOX_* image/config variables above this line.
# shellcheck shell=bash

usage() {
  cat <<'EOF'
devbox: isolated dev container with VS Code + Claude Code

Usage: devbox [command] [args]      (run from your project directory)

  up                Start the box (default command) and print the VS Code URL
  claude [args...]  Run Claude Code inside the box, e.g.
                      devbox claude --dangerously-skip-permissions
  shell             Open a bash shell inside the box
  exec CMD...       Run a command inside the box
  url               Print the VS Code URL again
  logs [dev|gw]     Container logs (gw shows allowed/blocked egress)
  status            Show what's running for this project
  down              Stop and remove containers + networks (keeps the home volume)
  destroy           down + delete the home volume (Claude login, IDE extensions, history)

Environment (read from the host, never from the workspace):
  DEVBOX_RUNTIME      podman | docker        (default: podman if installed)
  DEVBOX_PROJECT      project dir to mount   (default: $PWD)
  DEVBOX_PORT         host port for VS Code  (default: derived from project path)
  DEVBOX_FORWARD      extra ports to publish on 127.0.0.1, e.g. "5173 8080"
  DEVBOX_ALLOW        extra allowed domains for this run, e.g. "github.com crates.io"
  DEVBOX_MASK         extra file patterns to hide from the box, e.g. "secrets.yaml"
  DEVBOX_NO_IDE=1     don't start VS Code (Claude/shell only)
  DEVBOX_GIT_RW=1     let the box write .git/config and .git/hooks (default: read-only)
  DEVBOX_API_KEY=1    pass $ANTHROPIC_API_KEY into `devbox claude` (default: log in via /login)
  DEVBOX_MEMORY / DEVBOX_CPUS / DEVBOX_PIDS   resource limits (8g / 4 / 4096)
  DEVBOX_SUBNET       third+second octet override, e.g. "10.231.7" (for network clashes)
EOF
}

die() { echo "devbox: $*" >&2; exit 1; }
info() { echo "devbox: $*" >&2; }

# ---------------------------------------------------------------- runtime
RUNTIME="${DEVBOX_RUNTIME:-}"
if [ -z "$RUNTIME" ]; then
  if command -v podman >/dev/null 2>&1; then RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then RUNTIME=docker
  else die "neither podman nor docker found on PATH"
  fi
fi
command -v "$RUNTIME" >/dev/null 2>&1 || die "$RUNTIME not found on PATH"
rt() { "$RUNTIME" "$@"; }

# ---------------------------------------------------------------- project identity
PROJECT="$(realpath "${DEVBOX_PROJECT:-$PWD}")"
[ -d "$PROJECT" ] || die "project directory $PROJECT does not exist"
[ "$PROJECT" != "$HOME" ] && [ "$PROJECT" != "/" ] || die "refusing to mount $PROJECT; run from a project directory"

HASH="$(printf '%s' "$PROJECT" | sha256sum | cut -c1-8)"
BASE="$(basename "$PROJECT" | tr -c 'a-zA-Z0-9_.\n-' '-' | cut -c1-30)"
ID="${DEVBOX_PREFIX}-${BASE}-${HASH}"
DEV="$ID"
GW="$ID-gw"
NET_INT="$ID-int"
NET_EXT="$ID-ext"
HOME_VOL="$ID-home"

H=$((16#$HASH))
SUBNET="${DEVBOX_SUBNET:-10.$((200 + H % 50)).$(((H / 50) % 256))}"
GW_IP="$SUBNET.10"
DEV_IP="$SUBNET.20"
PORT="${DEVBOX_PORT:-$((20000 + H % 20000))}"

# ---------------------------------------------------------------- helpers
exists_container() { rt container inspect "$1" >/dev/null 2>&1; }
running() { [ "$(rt container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
exists_network() { rt network inspect "$1" >/dev/null 2>&1; }
exists_volume() { rt volume inspect "$1" >/dev/null 2>&1; }
label() { rt container inspect -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null; }

ensure_image() { # stream-script ref
  if ! rt image inspect "$2" >/dev/null 2>&1; then
    info "loading image $2"
    "$1" | rt load >/dev/null
  fi
}

tty_flags() { if [ -t 0 ] && [ -t 1 ]; then echo "-it"; else echo "-i"; fi; }

require_running() {
  running "$DEV" || die "not running for $PROJECT, start it with: devbox up"
}

print_url() {
  local token port
  token="$(label "$DEV" devbox.token)"
  port="$(label "$DEV" devbox.port)"
  if [ "$(label "$DEV" devbox.ide)" = "1" ]; then
    echo "VS Code:  http://127.0.0.1:${port}/?tkn=${token}"
  else
    echo "VS Code:  disabled (DEVBOX_NO_IDE=1)"
  fi
}

# ---------------------------------------------------------------- commands
cmd_up() {
  if running "$DEV" && running "$GW"; then
    info "already running for $PROJECT"
    print_url
    return
  fi
  # half-started or stopped leftovers
  rt rm -f "$DEV" "$GW" >/dev/null 2>&1 || true

  ensure_image "$DEVBOX_IMAGE_STREAM" "$DEVBOX_IMAGE_REF"
  ensure_image "$DEVBOX_GW_STREAM" "$DEVBOX_GW_REF"

  if ! exists_network "$NET_INT"; then
    rt network create --internal --subnet "$SUBNET.0/24" "$NET_INT" >/dev/null \
      || die "could not create network $SUBNET.0/24; set DEVBOX_SUBNET to a free range"
  fi
  exists_network "$NET_EXT" || rt network create "$NET_EXT" >/dev/null

  local host_uid host_gid
  host_uid="$(id -u)"
  host_gid="$(id -g)"
  if ! exists_volume "$HOME_VOL"; then
    rt volume create "$HOME_VOL" >/dev/null
    if [ "$RUNTIME" = docker ]; then
      # Docker runs the box as your host UID; make the home volume yours.
      rt run --rm --network none --user 0:0 --entrypoint /bin/chown \
        -v "$HOME_VOL:/home/dev" "$DEVBOX_IMAGE_REF" -R "$host_uid:$host_gid" /home/dev
    fi
  fi

  local token ide=1
  token="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
  [ "${DEVBOX_NO_IDE:-0}" = 1 ] && ide=0

  local common=(
    --cap-drop ALL
    --security-opt no-new-privileges
    --read-only
    --label "devbox.project=$PROJECT"
  )

  # ---- gateway: starts on the normal network (so ports can be published),
  #      then joins the internal network at a fixed address.
  local publish=() fwd=""
  if [ "$ide" = 1 ]; then
    publish+=(-p "127.0.0.1:$PORT:3000")
    fwd="3000"
  fi
  for p in ${DEVBOX_FORWARD:-}; do
    [[ "$p" =~ ^[0-9]+$ ]] || die "DEVBOX_FORWARD must be port numbers, got '$p'"
    publish+=(-p "127.0.0.1:$p:$p")
    fwd="$fwd $p"
  done

  rt run -d --name "$GW" "${common[@]}" \
    --network "$NET_EXT" "${publish[@]}" \
    --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
    --memory 256m --pids-limit 256 \
    -e "DEVBOX_TARGET=$DEV_IP" \
    -e "DEVBOX_FORWARD=$fwd" \
    -e "DEVBOX_EXTRA_ALLOW=${DEVBOX_ALLOW:-}" \
    "$DEVBOX_GW_REF" >/dev/null
  rt network connect --ip "$GW_IP" "$NET_INT" "$GW"

  # ---- dev container: internal network only, no DNS, egress via the gateway.
  local proxy="http://$GW_IP:3128" noproxy="localhost,127.0.0.1" tmpfs_opts="rw,nosuid,nodev,size=4g"
  local args=(
    run -d --name "$DEV" "${common[@]}"
    --hostname devbox
    --network "$NET_INT" --ip "$DEV_IP"
    --dns 127.0.0.1
    --add-host "proxy:$GW_IP"
    --tmpfs "/tmp:$tmpfs_opts"
    --memory "${DEVBOX_MEMORY:-8g}"
    --cpus "${DEVBOX_CPUS:-4}"
    --pids-limit "${DEVBOX_PIDS:-4096}"
    -w /workspace
    -e "HTTP_PROXY=$proxy" -e "HTTPS_PROXY=$proxy"
    -e "http_proxy=$proxy" -e "https_proxy=$proxy"
    -e "NO_PROXY=$noproxy" -e "no_proxy=$noproxy"
    -e "DEVBOX_IDE=$ide"
    -e "DEVBOX_TOKEN=$token"
    --label "devbox.token=$token"
    --label "devbox.port=$PORT"
    --label "devbox.ide=$ide"
  )

  # Commit identity (not credentials) from the host.
  local gname gemail
  gname="$(git config --global user.name 2>/dev/null || true)"
  gemail="$(git config --global user.email 2>/dev/null || true)"
  [ -n "$gname" ] && args+=(-e "GIT_AUTHOR_NAME=$gname" -e "GIT_COMMITTER_NAME=$gname")
  [ -n "$gemail" ] && args+=(-e "GIT_AUTHOR_EMAIL=$gemail" -e "GIT_COMMITTER_EMAIL=$gemail")

  # Map users so files the box writes into the workspace belong to you.
  local vopt=""
  if [ "$RUNTIME" = podman ]; then
    args+=(--userns "keep-id:uid=$DEVBOX_UID,gid=$DEVBOX_GID")
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = Enforcing ]; then
      vopt=":z"
    fi
  else
    args+=(--user "$host_uid:$host_gid")
  fi

  args+=(-v "$PROJECT:/workspace$vopt" -v "$HOME_VOL:/home/dev")

  # Git config and hooks run code on the HOST the next time you use git there.
  # Keep them read-only so the agent can't plant anything.
  if [ -d "$PROJECT/.git" ] && [ "${DEVBOX_GIT_RW:-0}" != 1 ]; then
    mkdir -p "$PROJECT/.git/hooks"
    args+=(-v "$PROJECT/.git/hooks:/workspace/.git/hooks:ro")
    [ -f "$PROJECT/.git/config" ] && args+=(-v "$PROJECT/.git/config:/workspace/.git/config:ro")
    # Custom hooks dir inside the repo (husky, lefthook, ...)?
    local hp
    hp="$(git -C "$PROJECT" config --local --get core.hooksPath 2>/dev/null || true)"
    if [ -n "$hp" ]; then
      case "$hp" in /*) ;; *) hp="$PROJECT/$hp" ;; esac
      hp="$(realpath -m "$hp")"
      if [ -d "$hp" ] && [[ "$hp" == "$PROJECT"/* ]]; then
        args+=(-v "$hp:/workspace/${hp#"$PROJECT"/}:ro")
      fi
    fi
  fi

  # Hide secret-looking files: bind /dev/null over files, empty tmpfs over dirs.
  local masked=0 masked_list="" f rel
  local -a find_expr=()
  set -f
  for pat in $DEVBOX_DEFAULT_MASKS ${DEVBOX_MASK:-}; do
    [ ${#find_expr[@]} -gt 0 ] && find_expr+=(-o)
    find_expr+=(-name "$pat")
  done
  set +f
  if [ ${#find_expr[@]} -gt 0 ]; then
    while IFS= read -r -d '' f; do
      case "$f" in *.example|*.sample|*.template) continue ;; esac
      rel="${f#"$PROJECT"/}"
      case "$rel" in *[:,]*) info "cannot hide '$rel' (':' or ',' in name); rename it"; continue ;; esac
      if [ -d "$f" ]; then
        args+=(--tmpfs "/workspace/$rel:ro,size=1k")
      else
        args+=(-v "/dev/null:/workspace/$rel:ro")
      fi
      masked=$((masked + 1))
      masked_list="$masked_list $rel"
    done < <(find "$PROJECT" -maxdepth 4 \
               \( -name node_modules -o -name .git -o -name .direnv -o -name target \) -prune -o \
               \( "${find_expr[@]}" \) -print0)
  fi

  args+=(--label "devbox.masked=${masked_list# }" "$DEVBOX_IMAGE_REF")

  if ! rt "${args[@]}" >/dev/null; then
    rt rm -f "$GW" >/dev/null 2>&1 || true
    die "failed to start the dev container"
  fi

  info "started $DEV ($RUNTIME), project: $PROJECT"
  [ "$masked" -gt 0 ] && info "hid $masked secret-looking path(s) from the box (see: devbox status)"
  print_url
  echo "Claude:   devbox claude"
  echo "Shell:    devbox shell"
}

cmd_exec() {
  require_running
  local env=()
  if [ "${DEVBOX_API_KEY:-0}" = 1 ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    env+=(-e ANTHROPIC_API_KEY)
  fi
  # shellcheck disable=SC2046
  exec "$RUNTIME" exec $(tty_flags) -w /workspace "${env[@]}" "$DEV" "$@"
}

cmd_status() {
  echo "project:  $PROJECT"
  echo "runtime:  $RUNTIME"
  echo "names:    $DEV, $GW, $NET_INT, $NET_EXT, $HOME_VOL"
  if running "$DEV"; then
    echo "state:    running"
    print_url
    local m
    m="$(label "$DEV" devbox.masked)"
    echo "hidden:   ${m:-(none)}"
  else
    echo "state:    stopped"
  fi
}

cmd_down() {
  rt rm -f "$DEV" "$GW" >/dev/null 2>&1 || true
  rt network rm "$NET_INT" "$NET_EXT" >/dev/null 2>&1 || true
  info "stopped $DEV (home volume $HOME_VOL kept)"
}

cmd_destroy() {
  cmd_down
  rt volume rm "$HOME_VOL" >/dev/null 2>&1 || true
  info "removed $HOME_VOL"
}

cmd="${1:-up}"
[ $# -gt 0 ] && shift
case "$cmd" in
  up|start) cmd_up ;;
  claude) cmd_exec claude "$@" ;;
  shell|sh) cmd_exec bash "$@" ;;
  exec) [ $# -gt 0 ] || die "usage: devbox exec CMD..."; cmd_exec "$@" ;;
  url|code) require_running; print_url ;;
  logs)
    case "${1:-gw}" in
      gw|gateway|proxy) exec "$RUNTIME" logs -f "$GW" ;;
      dev) exec "$RUNTIME" logs -f "$DEV" ;;
      *) die "logs: expected dev or gw" ;;
    esac ;;
  status|ps) cmd_status ;;
  down|stop) cmd_down ;;
  destroy) cmd_destroy ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac

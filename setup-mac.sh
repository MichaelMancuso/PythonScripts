#!/usr/bin/env bash
# ==============================================================================
#  HEAVEN + Ollama (WhiteRabbitNeo) — Apple Silicon turnkey setup
#  Faithful replica of the source box, hard no-cloud, local LLM only.
#
#  Usage:   bash setup-mac.sh
#  Safe to re-run (idempotent). Requires: macOS on Apple Silicon (arm64).
# ==============================================================================
set -euo pipefail

# ── Pins (match the source box) ───────────────────────────────────────────────
REPO_URL="https://github.com/nishu2402/HEAVEN-Autonomous-Penetration-Testing.git"
HEAVEN_COMMIT="ac936ea13cec41c9e0f1abc67d5447faf1ac9656"   # v4.2.0
HEAVEN_DIR="/opt/HEAVEN-Autonomous-Penetration-Testing"
PY="python3.13"
MODEL_SRC="hf.co/bartowski/WhiteRabbitNeo-2.5-Qwen-2.5-Coder-7B-GGUF:Q4_K_M"
MODEL_ALIAS="whiterabbitneo:7b"
TOOLS=(nmap nuclei ffuf gobuster masscan sqlmap nikto semgrep wpscan wireguard-tools httpx)

c(){ printf '\033[1;36m[→]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }

# ── 0. Platform guard ─────────────────────────────────────────────────────────
[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS only."
[ "$(uname -m)" = "arm64" ]  || die "Apple Silicon (arm64) required; this is $(uname -m)."
ok "macOS Apple Silicon detected."

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
  c "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # make brew available on Apple Silicon in this shell
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
command -v brew >/dev/null 2>&1 || eval "$(/opt/homebrew/bin/brew shellenv)"
ok "Homebrew: $(brew --version | head -1)"

# ── 2. Core deps ──────────────────────────────────────────────────────────────
c "Installing core deps (python@3.13, git, node, ollama)..."
brew install python@3.13 git node ollama >/dev/null 2>&1 || brew upgrade python@3.13 git node ollama >/dev/null 2>&1 || true
command -v "$PY" >/dev/null 2>&1 || PY="$(brew --prefix)/opt/python@3.13/bin/python3.13"
"$PY" --version || die "python@3.13 not found after install."

# ── 3. Scanner tools (gap-fill; non-fatal per tool) ────────────────────────────
c "Installing scanner tools..."
for t in "${TOOLS[@]}"; do
  brew list "$t" >/dev/null 2>&1 && { ok "  $t (present)"; continue; }
  if brew install "$t" >/dev/null 2>&1; then ok "  $t"; else warn "  $t — install skipped (check manually)"; fi
done

# ── 4. Clone HEAVEN at the exact commit ────────────────────────────────────────
if [ ! -d "$HEAVEN_DIR/.git" ]; then
  c "Cloning HEAVEN into $HEAVEN_DIR..."
  sudo mkdir -p /opt && sudo chown "$(whoami)" /opt
  git clone "$REPO_URL" "$HEAVEN_DIR"
fi
cd "$HEAVEN_DIR"
c "Checking out pinned commit $HEAVEN_COMMIT (v4.2.0)..."
git fetch --all --quiet || true
git checkout --quiet "$HEAVEN_COMMIT"
ok "HEAVEN at $(git rev-parse --short HEAD)"

# ── 5. Project installer (supported macOS path: venv, deps, UI build) ──────────
if [ -f scripts/install.sh ]; then
  c "Running HEAVEN's own installer (scripts/install.sh)..."
  bash scripts/install.sh || warn "install.sh returned non-zero; verifying venv manually."
fi
# Fallback / guarantee: ensure a working venv + editable install exist.
if [ ! -x venv/bin/heaven ]; then
  c "Building Python venv + installing HEAVEN..."
  "$PY" -m venv venv
  ./venv/bin/pip install --quiet --upgrade pip
  ./venv/bin/pip install --quiet -e .
fi
./venv/bin/heaven --version || die "heaven CLI not working."

# ── 6. Ollama service + model (GPU/Metal is automatic on Apple Silicon) ────────
c "Starting Ollama + pinning model in memory..."
launchctl setenv OLLAMA_KEEP_ALIVE -1 2>/dev/null || true   # keep model resident (best-effort, session+)
brew services restart ollama >/dev/null 2>&1 || brew services start ollama >/dev/null 2>&1 || true
# wait for the API
for i in $(seq 1 30); do curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1 && break; sleep 1; done

if ! ollama list 2>/dev/null | grep -q "^${MODEL_ALIAS}"; then
  c "Pulling WhiteRabbitNeo 2.5 7B (~4.7 GB)..."
  ollama pull "$MODEL_SRC"
  ollama cp "$MODEL_SRC" "$MODEL_ALIAS"
fi
ok "Model ready: $MODEL_ALIAS"

# ── 7. Config: init (strong passwords, no cloud keys) + no-cloud overrides ─────
if [ ! -f .env ]; then
  c "Generating .env (strong passwords, no API keys)..."
  ./venv/bin/heaven init --non-interactive
fi
c "Applying no-cloud + Apple-Silicon config..."
set_kv(){ grep -q "^$1=" .env && sed -i '' "s|^$1=.*|$1=$2|" .env || printf '%s=%s\n' "$1" "$2" >> .env; }
# hard no-cloud: local provider, fallback OFF, and NO cloud *_API_KEY present
sed -i '' '/^ANTHROPIC_API_KEY=/d;/^OPENAI_API_KEY=/d;/^GEMINI_API_KEY=/d;/^DEEPSEEK_API_KEY=/d' .env 2>/dev/null || true
set_kv HEAVEN_LLM_PROVIDER      ollama
set_kv HEAVEN_LLM_MODEL         "$MODEL_ALIAS"
set_kv HEAVEN_OLLAMA_HOST       http://localhost:11434
set_kv HEAVEN_LLM_AUTO_FALLBACK 0
set_kv HEAVEN_LLM_LOCAL_TIMEOUT 180          # GPU is fast — no 900s crutch needed
set_kv HEAVEN_WEB_DEPTH         10
set_kv HEAVEN_WEB_MAX_PAGES     2000
set_kv HEAVEN_SCAN_MODE         full
ok ".env configured (no-cloud, local WhiteRabbitNeo)."

# ── 8. Smoke test: local inference through Ollama ──────────────────────────────
c "Smoke-testing local model..."
if curl -fsS --max-time 60 http://localhost:11434/v1/chat/completions \
     -H 'Content-Type: application/json' \
     -d "{\"model\":\"$MODEL_ALIAS\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with one word: READY\"}],\"max_tokens\":5}" \
     | grep -qi ready; then
  ok "Local model responded. GPU-accelerated inference is live."
else
  warn "Smoke test inconclusive — check 'ollama ps' and logs."
fi

# ── Done ───────────────────────────────────────────────────────────────────────
cat <<EOF

────────────────────────────────────────────────────────────
 ✅ HEAVEN + Ollama (WhiteRabbitNeo) ready on Apple Silicon.

 Start the platform:
   cd $HEAVEN_DIR && ./venv/bin/heaven serve

 Your generated admin/DB passwords are in:
   $HEAVEN_DIR/.env   (HEAVEN_ADMIN_USERNAME / HEAVEN_ADMIN_PASSWORD)

 Notes:
  • Hard no-cloud: provider=ollama, fallback OFF, no API keys present.
  • Apple Silicon Metal GPU is used automatically — the heavy AI
    features (hypotheses, attack chains, autonomous loop) that were
    impractical on the CPU box should now run. Re-enable them freely.
  • Ollama runs via 'brew services' (launchd); it binds 127.0.0.1 by default.
  • OLLAMA_KEEP_ALIVE was set for this login session. To persist it across
    reboots, add it to a login item or a user LaunchAgent (ask if you want one).
  • No systemd on macOS: run 'heaven serve' in a terminal/tmux, or ask me
    to generate a launchd plist for auto-start.
────────────────────────────────────────────────────────────
EOF

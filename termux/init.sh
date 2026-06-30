#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

info() { echo -e "\n[INFO]  $*"; }
warn() { echo -e "\n[WARN]  $*" >&2; }
die() { echo -e "\n[ERROR] $*" >&2; exit 1; }
confirm() { read -rp "$1 [y/N] " _ans; [[ "${_ans,,}" == y* ]]; }

[[ -d /data/data/com.termux ]] || die "This script must run inside Termux on Android."
command -v apt >/dev/null 2>&1 || die "'apt' not found — is this a fresh Termux install?"

info "Welcome to Termux setup! This script will configure your environment, install core tools, and set up an SSH server for remote access."

export SSHD_PORT=2222
APT_OPTS=(-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

cd "${HOME}" || die "Failed to change directory to ${HOME}."

info "Setting mirror to Cloudflare CDN..."
# echo "deb https://ftp.fau.de/termux/termux-main stable main" > "${PREFIX}/etc/apt/sources.list"
echo "deb https://packages-cf.termux.dev/apt/termux-main stable main" > "${PREFIX}/etc/apt/sources.list"

mkdir -p "${PREFIX}/etc/apt/sources.list.d"

info "Adding X11 repository for GUI apps..."
echo "deb https://packages-cf.termux.dev/apt/termux-x11 x11 main" > "${PREFIX}/etc/apt/sources.list.d/x11.list"

info "Requesting storage permission..."
echo ""
echo "A system dialog will appear asking for storage access."
echo "Tap 'Allow' to enable access to /sdcard and Downloads."
echo ""
termux-setup-storage || warn "Storage setup skipped or already done."
echo "Waiting for storage access..."
for i in $(seq 1 30); do
  [[ -d "${HOME}/storage/shared" ]] && break
  sleep 1
done
[[ -d "${HOME}/storage/shared" ]] || warn "Storage not accessible after 30s — grant permission manually if needed."

info "Preparing directories..."
ln -s "${HOME}/storage/shared" "${HOME}/sdcard" 2>/dev/null || true

mkdir -p "${HOME}/.local/bin" "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

info "Installing core tools..."
apt update && apt upgrade -y "${APT_OPTS[@]}"

apt install -y --no-install-recommends "${APT_OPTS[@]}" \
  git \
  openssh \
  tar \
  zip \
  htop \
  which \
  mandoc \
  python \
  python-pip \
  bash-completion \
  file \
  iproute2 \
  util-linux \
  termux-api \
  termux-services \
  termux-exec \
  termux-tools \
  termux-auth \
  neofetch

info "Setting up motd..."
echo "Bonjour !!!" > "${PREFIX}/etc/motd"

info "Setting up bash completions..."

info "Create ~/.bashrc..."
cat > "${HOME}/.bashrc" <<'EOF'
export PATH="${HOME}/.local/bin:${PATH}"

if [[ -f "${PREFIX}/share/bash-completion/bash_completion" ]]; then
  . "${PREFIX}/share/bash-completion/bash_completion"
fi

if [[ -f "${HOME}/.alias" ]]; then
  . "${HOME}/.alias"
fi

export LD_LIBRARY_PATH="/vendor/lib64:${HOME}/.local/lib:${PREFIX}/lib:${LD_LIBRARY_PATH:-}"

EOF

info "Create ~/.alias..."
cat > "${HOME}/.alias" <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lh='ls -lh'
alias lt='ls -ltr'
alias lsize='ls -lSh'
alias du='du -sh ./*/'
alias dir-size='du -cksh * | sort -h'
alias ram="free -h"
alias 'cd..'="cd .."
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# termux package manager
alias pki='pkg install'
alias pkr='pkg remove'
alias pku='pkg update && pkg upgrade'
alias pks='pkg search'

# network
alias myip='curl -s ifconfig.me && echo'
alias ports='ss -tuln'
alias pingg='ping -c 4 google.com'

# processes
alias psa='ps aux'
alias psg='ps aux | grep'

# python
alias py='python3'

# git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# misc
alias cls='clear'
alias h='history'
alias path='echo $PATH | tr ":" "\n"'
alias reload='source ~/.bashrc && echo "reloaded"'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias week='date +%V'

EOF

##################################################################################
info "Checking host keys..."
for type in rsa ecdsa ed25519; do
  key="$PREFIX/etc/ssh/ssh_host_${type}_key"
  if [[ ! -f "$key" ]]; then
    info "Generating $type host key..."
    ssh-keygen -t "$type" -f "$key" -N "" -q
  fi
done

if [[ ! -f "${HOME}/.ssh/authorized_keys" ]]; then
  touch "${HOME}/.ssh/authorized_keys"
  chmod 600 "${HOME}/.ssh/authorized_keys"
  warn "No authorized_keys found. Add your public key to ~/.ssh/authorized_keys to enable key-based login."
else
  chmod 600 "${HOME}/.ssh/authorized_keys"
fi

SSHD_CONFIG="${PREFIX}/etc/ssh/sshd_config"

info "Writing sshd_config..."
cat > "${SSHD_CONFIG}" <<EOF
Port ${SSHD_PORT}
ListenAddress 0.0.0.0

HostKey ${PREFIX}/etc/ssh/ssh_host_rsa_key
HostKey ${PREFIX}/etc/ssh/ssh_host_ecdsa_key
HostKey ${PREFIX}/etc/ssh/ssh_host_ed25519_key

PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
ChallengeResponseAuthentication no

Subsystem sftp ${PREFIX}/libexec/sftp-server
EOF

chmod 600 "${SSHD_CONFIG}"

if pgrep -x sshd >/dev/null 2>&1; then
  info "sshd already running — restarting with new config..."
  pkill -x sshd || true
  sleep 1
fi

IP=$(ip route get 1.1.1.1 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' \
  | head -1) || true

if command -v sv-enable >/dev/null 2>&1; then
  sv-enable sshd 2>/dev/null \
    || warn "Could not register sshd service. Restart Termux, then run: sv-enable sshd"

  if pgrep -x runsvdir >/dev/null 2>&1; then
    sv start sshd 2>/dev/null \
      || warn "Could not start sshd service. Run: sv start sshd"
  else
    # runsvdir not running yet (termux-services was just installed this session)
    # start sshd directly; it will auto-start via termux-services after next Termux restart
    sshd 2>/dev/null \
      || warn "Could not start sshd directly. Restart Termux to auto-start via termux-services."
    warn "termux-services daemon not active yet — sshd started directly. Restart Termux to enable auto-start."
  fi
else
  warn "termux-services not active in this session. Restart Termux, then run: sv-enable sshd && sv start sshd"
fi

##################################################################################

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo "  SSH server ready"
echo "  Port   : ${SSHD_PORT}"
echo "  User   : $(whoami)"
echo "  Connect: ssh $(whoami)@${IP:-<device-ip>} -p ${SSHD_PORT}"
echo ""
echo "  Add your public key:"
echo "  ~/.ssh/authorized_keys"
echo "============================================"
echo ""
echo "Useful next steps:"
echo "  • Run '. ~/.bashrc' to reload PATH"
echo "  • Verify:          python --version"
echo "  • Install extras:  apt install ffmpeg imagemagick"
echo "  • For GUI/X11:     pkg install x11-repo && apt install xorg tigervnc xfce4"
echo "============================================"

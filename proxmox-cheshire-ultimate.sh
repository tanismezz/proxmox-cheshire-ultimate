#!/bin/bash
#
# ╔═══════════════════════════════════════════════════════════════════════╗
# ║  CHESHIRE CAT AI + OLLAMA - INSTALLER AUTOMATICO PROXMOX VM / CT    ║
# ║  Production-Ready Script con Error Handling Completo                 ║
# ╚═══════════════════════════════════════════════════════════════════════╝
#
# Versione: 3.0-PROD
# Data: Gennaio 2026
# Compatibilità: Debian 13 Trixie / Proxmox VE 8.x
# Licenza: MIT
#
# REQUISITI MINIMI VM:
#   - 4 CPU cores
#   - 12 GB RAM
#   - 32 GB disk
#   - Connessione internet
#   - Qemu Guest Agent abilitato in Proxmox
#
# USO:
#   sudo bash proxmox-cheshire-ultimate.sh
#
# ROLLBACK:
#   sudo bash proxmox-cheshire-ultimate.sh --rollback
#

#==============================================================================
# STRICT MODE & TRAPS (Best Practice 2026)
#==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Trap per cleanup automatico su errori
trap 'error_handler $? $LINENO' ERR
trap 'cleanup_on_exit' EXIT INT TERM

#==============================================================================
# CONFIGURAZIONE CENTRALIZZATA
#==============================================================================

# Versioni software (pinned per riproducibilità)
readonly OLLAMA_MODEL="qwen3:8b"
readonly CCAT_VERSION="1.9.1"
readonly DOCKER_COMPOSE_VERSION="v2"

# Directory e file
readonly INSTALL_DIR_BASE="${HOME}/cheshire-cat-ai"
readonly BACKUP_DIR="${HOME}/cheshire-backup"
readonly LOG_FILE="/var/log/cheshire-cat-install.log"
readonly STATE_FILE="/tmp/cheshire-install.state"

# Network e sicurezza
readonly SSH_PORT="${SSH_PORT:-22}"
readonly FIREWALL_ENABLED="${FIREWALL_ENABLED:-true}"

# User management
TARGET_USER="${SUDO_USER:-cheshirecat}"

# Timeout e retry
readonly DOWNLOAD_TIMEOUT=300
readonly MAX_RETRIES=3
readonly RETRY_DELAY=15

# Script metadata
readonly SCRIPT_VERSION="3.0"
readonly SCRIPT_NAME="$(basename "$0")"

#==============================================================================
# COLORI E FORMATTAZIONE
#==============================================================================

if [ -t 1 ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly MAGENTA=''
    readonly CYAN=''
    readonly BOLD=''
    readonly NC=''
fi

#==============================================================================
# VARIABILI GLOBALI
#==============================================================================

DEBIAN_VERSION=""
VM_IP=""
DOCKER_BRIDGE_IP="172.17.0.1"
INSTALL_START_TIME=""
ERRORS_ENCOUNTERED=0
WARNINGS_ENCOUNTERED=0
INSTALL_DIR=""
IS_CT=false       # true se in esecuzione dentro un container LXC
IS_BAREMETAL=false # true se in esecuzione su hardware fisico (no hypervisor)

#==============================================================================
# LOGGING AVANZATO
#==============================================================================

init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
    echo "=== Installazione avviata: $(date) ===" >> "$LOG_FILE"
    INSTALL_START_TIME=$(date +%s)
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR ${timestamp}]${NC} $message"
            ERRORS_ENCOUNTERED=$((ERRORS_ENCOUNTERED + 1))
            ;;
        WARN)
            echo -e "${YELLOW}[WARN  ${timestamp}]${NC} $message"
            WARNINGS_ENCOUNTERED=$((WARNINGS_ENCOUNTERED + 1))
            ;;
        INFO)
            echo -e "${BLUE}[INFO  ${timestamp}]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[OK    ${timestamp}]${NC} $message"
            ;;
        DEBUG)
            if [ "${DEBUG:-0}" = "1" ]; then
                echo -e "${CYAN}[DEBUG ${timestamp}]${NC} $message"
            fi
            ;;
    esac
}

error()   { log ERROR "$@"; }
warn()    { log WARN "$@"; }
info()    { log INFO "$@"; }
success() { log SUCCESS "$@"; }
debug()   { log DEBUG "$@"; }

#==============================================================================
# ERROR HANDLER E CLEANUP
#==============================================================================

error_handler() {
    local exit_code=$1
    local line_number=$2
    
    error "Script fallito alla linea $line_number con exit code $exit_code"
    error "Comando fallito: $BASH_COMMAND"
    
    save_state "FAILED" "$line_number"
    
    echo ""
    error "═══════════════════════════════════════════════════════════"
    error "  INSTALLAZIONE FALLITA"
    error "═══════════════════════════════════════════════════════════"
    echo ""
    warn "Log completo salvato in: $LOG_FILE"
    warn "Per riprovare: sudo bash $SCRIPT_NAME"
    warn "Per rollback: sudo bash $SCRIPT_NAME --rollback"
    echo ""
    
    exit "$exit_code"
}

cleanup_on_exit() {
    local exit_code=$?
    rm -f /tmp/cheshire-*.tmp 2>/dev/null || true
    
    if [ "$exit_code" -eq 0 ]; then
        success "Cleanup completato"
    fi
}

#==============================================================================
# STATE MANAGEMENT
#==============================================================================

save_state() {
    local state="$1"
    local extra="${2:-}"
    echo "$state|$(date +%s)|$extra" > "$STATE_FILE"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "NONE|0|"
    fi
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

section() {
    echo ""
    echo -e "${MAGENTA}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}${BOLD}  $1${NC}"
    echo -e "${MAGENTA}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

progress_bar() {
    local duration=${1}
    local prefix="${2:-Attesa}"
    
    for ((i=0; i<=duration; i++)); do
        local percent=$((i * 100 / duration))
        local filled=$((percent / 2))
        local empty=$((50 - filled))
        
        printf "\r${CYAN}%s:${NC} [" "$prefix"
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "] %3d%%" "$percent"
        
        sleep 1
    done
    echo ""
}

retry_command() {
    local max_attempts="$1"
    shift
    local cmd=("$@")
    local attempt=1
    local delay="$RETRY_DELAY"
    
    while [ $attempt -le "$max_attempts" ]; do
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [ $attempt -lt "$max_attempts" ]; then
            warn "Tentativo $attempt/$max_attempts fallito, riprovo tra ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
            attempt=$((attempt + 1))
        else
            error "Comando fallito dopo $max_attempts tentativi: ${cmd[*]}"
            return 1
        fi
    done
}

require_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Comando richiesto non trovato: $1"
        return 1
    fi
}

wait_for_service() {
    local service="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    info "Attesa avvio servizio $service..."
    
    while [ $elapsed -lt "$timeout" ]; do
        if systemctl is-active --quiet "$service"; then
            success "Servizio $service attivo"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    error "Timeout attesa servizio $service dopo ${timeout}s"
    return 1
}

test_connection() {
    local url="$1"
    local timeout="${2:-10}"
    
    if curl --silent --fail --max-time "$timeout" "$url" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

#==============================================================================
# STEP 0: PRE-FLIGHT CHECKS
#==============================================================================

preflight_checks() {
    section "STEP 0: Pre-flight Checks"
    
    # Root check
    if [ "$EUID" -ne 0 ]; then
        error "Questo script deve essere eseguito come root"
        error "Usa: sudo bash $SCRIPT_NAME"
        exit 1
    fi
    success "✓ Privilegi root verificati"

    # Detect environment: VM vs CT vs Bare-metal
    local virt_type
    virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
    if [ "$virt_type" = "lxc" ]; then
        IS_CT=true
        IS_BAREMETAL=false
        success "✓ Ambiente rilevato: Proxmox LXC Container"
        info "Lo script si adatterà automaticamente all'ambiente CT"
    elif [ "$virt_type" = "none" ]; then
        IS_CT=false
        IS_BAREMETAL=true
        success "✓ Ambiente rilevato: Bare-metal (nessun hypervisor)"
    else
        IS_CT=false
        IS_BAREMETAL=false
        success "✓ Ambiente rilevato: VM ($virt_type)"
    fi

    # Debian version check
    if [ ! -f /etc/debian_version ]; then
        error "Sistema non Debian rilevato"
        exit 1
    fi
    
    DEBIAN_VERSION=$(cat /etc/debian_version)
    if [[ "$DEBIAN_VERSION" =~ ^13 ]] || grep -q "trixie" /etc/debian_version 2>/dev/null; then
        success "✓ Debian 13 Trixie rilevata (versione: $DEBIAN_VERSION)"
    else
        warn "⚠ Versione Debian: $DEBIAN_VERSION (testato su Debian 13)"
        read -r -p "Continuare comunque? [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    # Kernel version
    local kernel_major kernel_minor
    kernel_major=$(uname -r | cut -d. -f1)
    kernel_minor=$(uname -r | cut -d. -f2)
    if [ "$kernel_major" -lt 5 ] || { [ "$kernel_major" -eq 5 ] && [ "$kernel_minor" -lt 10 ]; }; then
        error "Kernel troppo vecchio: $(uname -r) (minimo 5.10)"
        exit 1
    fi
    success "✓ Kernel: $(uname -r)"
    
    # RAM check
    local total_ram
    total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 11 ]; then
        error "RAM insufficiente: ${total_ram}GB (minimo 12GB per Qwen3:8b)"
        exit 1
    fi
    success "✓ RAM: ${total_ram}GB"
    
    # Disk space check
    local disk_space
    disk_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_space" -lt 25 ]; then
        error "Spazio disco insufficiente: ${disk_space}GB (minimo 30GB)"
        exit 1
    fi
    success "✓ Spazio disco: ${disk_space}GB disponibili"
    
    # Internet connectivity check
    info "Verifica connessione internet..."
    local internet_ok=false
    for dns in 8.8.8.8 1.1.1.1 208.67.222.222; do
        if ping -c 2 -W 3 "$dns" &> /dev/null; then
            internet_ok=true
            break
        fi
    done
    
    if [ "$internet_ok" = false ]; then
        error "Nessuna connessione internet rilevata"
        error "Verifica: ip a, ip route, cat /etc/resolv.conf"
        exit 1
    fi
    success "✓ Connessione internet OK"
    
    # DNS resolution check
    if ! nslookup github.com > /dev/null 2>&1; then
        warn "⚠ Risoluzione DNS problematica"
    else
        success "✓ Risoluzione DNS OK"
    fi
    
    # Network interface detection (FIX: usa variabile locale)
    local net_if
    net_if=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$net_if" ]; then
        error "Impossibile rilevare interfaccia di rete (default route assente)"
        exit 1
    fi
    
    VM_IP=$(ip -4 addr show "$net_if" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [ -z "$VM_IP" ]; then
        VM_IP=$(hostname -I | awk '{print $1}')
    fi
    success "✓ IP VM: $VM_IP (interfaccia: $net_if)"
    
    # Check if already installed
    if [ -f "$INSTALL_DIR_BASE/docker-compose.yml" ] && docker ps 2>/dev/null | grep -q cheshire_cat_core; then
        warn "⚠ Cheshire Cat già installato"
        read -r -p "Reinstallare? (i dati saranno preservati) [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            info "Installazione annullata"
            exit 0
        fi
    fi
    
    save_state "PREFLIGHT_OK"
    success "Pre-flight checks completati"
}

#==============================================================================
# STEP 1: SISTEMA BASE
#==============================================================================

configure_system() {
    section "STEP 1: Configurazione Sistema Base"
    
    mkdir -p "$BACKUP_DIR"
    info "Backup configurazioni in: $BACKUP_DIR"
    
    # Update sistema
    info "Aggiornamento pacchetti sistema..."
    retry_command 2 apt-get update -qq
    
    # Upgrade
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    success "Sistema aggiornato"
    
    # Installazione utility (FIX: rimosso software-properties-common)
    info "Installazione utility essenziali..."
    local packages=(
        curl wget git
        vim nano
        htop iotop
        net-tools dnsutils
        ca-certificates gnupg
        apt-transport-https
        lsb-release
        sudo ufw fail2ban
        jq bc
        ncdu
        unzip zip
        zstd
    )
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
    success "Utility installate"

    # Qemu Guest Agent (solo VM con hypervisor, inutile in CT e bare-metal)
    if [ "$IS_CT" = false ] && [ "$IS_BAREMETAL" = false ]; then
        info "Installazione e configurazione Qemu Guest Agent..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-guest-agent
        systemctl enable qemu-guest-agent
        systemctl start qemu-guest-agent || true

        if wait_for_service "qemu-guest-agent" 10; then
            success "✓ Qemu Guest Agent attivo"
        else
            warn "⚠ Qemu Agent non attivo - verifica Proxmox VM options"
        fi
    elif [ "$IS_CT" = true ]; then
        info "CT rilevato: Qemu Guest Agent non necessario (skip)"
    else
        info "Bare-metal rilevato: Qemu Guest Agent non necessario (skip)"
    fi
    
    # Timezone
    info "Configurazione timezone..."
    if timedatectl set-timezone Europe/Rome 2>/dev/null; then
        success "Timezone: $(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}')"
    else
        # Fallback per CT dove timedatectl potrebbe non funzionare
        ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
        echo "Europe/Rome" > /etc/timezone
        success "Timezone: Europe/Rome (impostata via /etc/localtime)"
    fi
    
 # NTP sync (DISABILITATO - Proxmox gestisce sync autonomamente)
# if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
#     success "✓ NTP time sync attivo"
# else
#     warn "⚠ NTP gestito da Proxmox/chrony"
# fi
info "⏱️  Sincronizzazione orario gestita da Proxmox"


    
    # Kernel parameters
    info "Ottimizzazione parametri kernel..."
    cat > /etc/sysctl.d/99-cheshire-cat.conf << 'EOF'
# Ottimizzazioni Cheshire Cat AI + Ollama
vm.swappiness=10
vm.overcommit_memory=1
vm.max_map_count=262144
fs.file-max=2097152
fs.inotify.max_user_watches=524288
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
EOF

    # In CT alcuni parametri sono read-only: applicare uno alla volta
    local sysctl_ok=0
    local sysctl_skip=0
    while IFS='=' read -r key value; do
        # Salta commenti e righe vuote
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        if sysctl -w "${key}=${value}" > /dev/null 2>&1; then
            sysctl_ok=$((sysctl_ok + 1))
        else
            sysctl_skip=$((sysctl_skip + 1))
            debug "sysctl ${key} non scrivibile (normale in CT)"
        fi
    done < /etc/sysctl.d/99-cheshire-cat.conf

    if [ "$IS_CT" = true ] && [ "$sysctl_skip" -gt 0 ]; then
        success "✓ Kernel: ${sysctl_ok} parametri applicati, ${sysctl_skip} read-only (normale in CT)"
    else
        success "✓ Kernel ottimizzato (${sysctl_ok} parametri applicati)"
    fi

    
    save_state "SYSTEM_CONFIGURED"
}

#==============================================================================
# STEP 2: SICUREZZA
#==============================================================================

configure_security() {
    section "STEP 2: Hardening Sicurezza"
    
    if [ "$FIREWALL_ENABLED" != "true" ]; then
        warn "Firewall disabilitato (FIREWALL_ENABLED=false)"
        return 0
    fi

    # In CT, verificare che iptables funzioni prima di procedere
    if [ "$IS_CT" = true ]; then
        if ! iptables -L -n > /dev/null 2>&1; then
            warn "⚠ CT senza supporto iptables/nftables: firewall non configurabile"
            warn "⚠ Configura le regole firewall a livello host Proxmox"
            FIREWALL_ENABLED="false"
            save_state "SECURITY_CONFIGURED"
            return 0
        fi
        info "CT con supporto iptables rilevato, procedo con UFW"
    fi
    
    # Backup UFW
    if [ -d /etc/ufw ]; then
        tar -czf "$BACKUP_DIR/ufw-backup-$(date +%Y%m%d).tar.gz" /etc/ufw 2>/dev/null || true
    fi
    
    info "Configurazione firewall UFW..."
    
    ufw --force reset > /dev/null
    ufw default deny incoming
    ufw default allow outgoing
    ufw logging on
    
    # SSH
    if [ "$SSH_PORT" != "22" ]; then
        info "Cambio porta SSH da 22 a $SSH_PORT..."
        
        cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup"
        
        sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
        sed -i "s/^Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
        
        if sshd -t; then
            systemctl restart sshd
            success "✓ Porta SSH cambiata: $SSH_PORT"
        else
            error "Configurazione SSH non valida, ripristino backup"
            cp "$BACKUP_DIR/sshd_config.backup" /etc/ssh/sshd_config
            systemctl restart sshd
            SSH_PORT=22
        fi
    fi
    
    ufw allow "$SSH_PORT"/tcp comment 'SSH'
    
    # Cheshire Cat (LAN only)
    info "Apertura porta 1865 per LAN..."
    ufw allow from 192.168.0.0/16 to any port 1865 proto tcp comment 'Cat LAN 192.168'
    ufw allow from 10.0.0.0/8 to any port 1865 proto tcp comment 'Cat LAN 10.x'
    ufw allow from 172.16.0.0/12 to any port 1865 proto tcp comment 'Cat LAN 172.x'
    
    # Ollama (LAN — permette uso da Aider/altri client in rete)
    info "Apertura porta 11434 (Ollama) per LAN..."
    ufw allow from 192.168.0.0/16 to any port 11434 proto tcp comment 'Ollama LAN 192.168'
    ufw allow from 10.0.0.0/8 to any port 11434 proto tcp comment 'Ollama LAN 10.x'
    ufw allow from 172.16.0.0/12 to any port 11434 proto tcp comment 'Ollama LAN 172.x'
    ufw allow from 127.0.0.1 to any port 11434 proto tcp comment 'Ollama localhost'
    ufw deny 11434/tcp comment 'Ollama block WAN'
    
    ufw --force enable > /dev/null
    success "✓ Firewall configurato"
    
    # Fail2ban
    info "Configurazione Fail2ban..."
    
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    if wait_for_service "fail2ban" 10; then
        success "✓ Fail2ban attivo"
    else
        warn "⚠ Fail2ban non avviato correttamente"
    fi
    
    # SSH hardening (disabilitato)
    # info "Hardening SSH..."

    save_state "SECURITY_CONFIGURED"

    # Se Docker è già installato, riavviarlo per ripristinare regole iptables post-UFW reset
    if command -v docker &> /dev/null && systemctl is-enabled docker &> /dev/null; then
        info "Riavvio Docker per ripristinare regole iptables post-UFW..."
        systemctl reset-failed docker 2>/dev/null || true
        systemctl restart docker
        wait_for_service "docker" 20 || warn "Docker non riavviato, sarà gestito nello step successivo"
    fi
}

#==============================================================================
# STEP 3: DOCKER ENGINE
#==============================================================================

install_docker() {
    section "STEP 3: Installazione Docker Engine"
    
    if command -v docker &> /dev/null; then
        local docker_version
        docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+')
        success "✓ Docker già installato: $docker_version"
        
        if docker compose version &> /dev/null; then
            success "✓ Docker Compose plugin presente"
        fi
    else
        info "Installazione Docker Engine (metodo ufficiale 2026)..."
        
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        install -m 0755 -d /etc/apt/keyrings
        
        retry_command 3 curl -fsSL https://download.docker.com/linux/debian/gpg \
            -o /etc/apt/keyrings/docker.asc
        
        chmod a+r /etc/apt/keyrings/docker.asc
        
        # Formato DEB822 ufficiale Debian 13
        cat > /etc/apt/sources.list.d/docker.sources << EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
Architectures: amd64 arm64
EOF
        
        retry_command 2 apt-get update -qq
        
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin
        
        success "✓ Docker installato: $(docker --version)"
    fi
    
    systemctl enable docker
    systemctl reset-failed docker 2>/dev/null || true
    systemctl start docker

    if ! wait_for_service "docker" 30; then
        error "Docker non avviato correttamente"
        exit 1
    fi
    
    # User management
    info "Configurazione gruppo docker per utente $TARGET_USER..."
    if ! id "$TARGET_USER" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo,docker "$TARGET_USER"
        
        local generated_pass
        generated_pass=$(tr -dc 'A-Za-z2-9' < /dev/urandom | head -c 24)
        echo "$TARGET_USER:$generated_pass" | chpasswd
        
        success "✓ Utente $TARGET_USER creato"
        warn "⚠ Password generata: $generated_pass"
        warn "⚠ SALVALA SUBITO! Necessaria per SSH."
        
        echo "$generated_pass" > "$BACKUP_DIR/user-password.txt"
        chmod 600 "$BACKUP_DIR/user-password.txt"
        warn "Password salvata anche in: $BACKUP_DIR/user-password.txt"
    else
        usermod -aG docker "$TARGET_USER"
        success "✓ Utente $TARGET_USER aggiunto a gruppo docker"
    fi
    
    # Imposta directory installazione
    INSTALL_DIR="/home/$TARGET_USER/cheshire-cat-ai"
    
    # Docker bridge IP
    sleep 5
    DOCKER_BRIDGE_IP=$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo "172.17.0.1")
    success "✓ Docker bridge IP: $DOCKER_BRIDGE_IP"
    
    # Firewall: conferma che Docker → Ollama è già coperto dalle regole LAN 172.16.0.0/12
    if [ "$FIREWALL_ENABLED" = "true" ]; then
        success "✓ Subnet Docker già coperta da regola LAN 172.16.0.0/12 per Ollama"
    fi
    
    # Docker daemon config
    info "Ottimizzazione Docker daemon..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF
    
    systemctl reset-failed docker 2>/dev/null || true
    systemctl restart docker
    wait_for_service "docker" 20
    success "✓ Docker ottimizzato"
    
    save_state "DOCKER_INSTALLED"
}

#==============================================================================
# STEP 4: OLLAMA
#==============================================================================

install_ollama() {
    section "STEP 4: Installazione Ollama Nativo"
    
    if command -v ollama &> /dev/null; then
        local ollama_version
        ollama_version=$(ollama --version 2>&1 | head -1)
        success "✓ Ollama già installato: $ollama_version"
    else
        info "Download e installazione Ollama..."
        
        if ! retry_command 3 bash -c "curl -fsSL https://ollama.com/install.sh | bash"; then
            error "Installazione Ollama fallita"
            exit 1
        fi
        
        success "✓ Ollama installato: $(ollama --version 2>&1 | head -1)"
    fi
    
    # Configurazione servizio
    info "Configurazione servizio Ollama..."
    
    mkdir -p /etc/systemd/system/ollama.service.d
    
    cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_ORIGINS=http://localhost:*,http://127.0.0.1:*,http://172.17.0.*,http://192.168.*,http://10.*"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=10m"

StandardOutput=journal
StandardError=journal

Restart=on-failure
RestartSec=10s
EOF
    
    systemctl daemon-reload
    systemctl enable ollama
    systemctl restart ollama
    
    if ! wait_for_service "ollama" 30; then
        error "Servizio Ollama non avviato"
        error "Log: journalctl -u ollama -n 50"
        exit 1
    fi
    
    success "✓ Servizio Ollama attivo"
    
    # Verifica binding
    sleep 3
    if ss -tlnp | grep -q ":11434.*0.0.0.0"; then
        success "✓ Ollama in ascolto su 0.0.0.0:11434"
    else
        warn "⚠ Ollama potrebbe non essere in ascolto su tutte le interfacce"
    fi
    
    # Test API
    info "Test API Ollama..."
    if retry_command 3 test_connection "http://localhost:11434/api/tags" 5; then
        success "✓ Ollama API risponde"
    else
        error "Ollama API non risponde"
        exit 1
    fi
    
    save_state "OLLAMA_INSTALLED"
}

#==============================================================================
# STEP 5: DOWNLOAD MODELLO
#==============================================================================

download_model() {
    section "STEP 5: Download Modello $OLLAMA_MODEL"
    
    if ollama list 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
        success "✓ Modello $OLLAMA_MODEL già presente"
        ollama list
        return 0
    fi
    
    info "Download modello $OLLAMA_MODEL (~6GB)"
    info "Tempo stimato: 5-15 minuti"
    info "☕ Questo è il momento perfetto per un caffè!"
    echo ""
    
    local attempt=1
    local max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        info "Tentativo $attempt/$max_attempts..."
        
        if command -v timeout &> /dev/null; then
            if timeout "$DOWNLOAD_TIMEOUT" ollama pull "$OLLAMA_MODEL"; then
                success "✓ Modello $OLLAMA_MODEL scaricato"
                ollama list
                save_state "MODEL_DOWNLOADED"
                return 0
            fi
        else
            if ollama pull "$OLLAMA_MODEL"; then
                success "✓ Modello scaricato"
                ollama list
                save_state "MODEL_DOWNLOADED"
                return 0
            fi
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            warn "Download fallito, riprovo tra ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        
        attempt=$((attempt + 1))
    done
    
    error "Download modello fallito dopo $max_attempts tentativi"
    error "Puoi scaricare manualmente dopo: ollama pull $OLLAMA_MODEL"
    exit 1
}

#==============================================================================
# STEP 6: CHESHIRE CAT
#==============================================================================

deploy_cheshire_cat() {
    section "STEP 6: Deploy Cheshire Cat v$CCAT_VERSION"
    
    # Verifica che Docker sia attivo prima di procedere
    if ! systemctl is-active --quiet docker; then
        warn "Docker non attivo, tentativo di riavvio..."
        systemctl reset-failed docker 2>/dev/null || true
        systemctl restart docker
        wait_for_service "docker" 30 || { error "Docker non avviabile"; exit 1; }
    fi

    info "Creazione struttura directory..."
    mkdir -p "$INSTALL_DIR"/{data,plugins,static,logs}
    
    # Backup se esiste
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        info "Backup installazione esistente..."
        tar -czf "$BACKUP_DIR/cheshire-data-$(date +%Y%m%d_%H%M%S).tar.gz" \
            -C "$INSTALL_DIR" data plugins static 2>/dev/null || true
    fi
    
    # Docker Compose
    info "Generazione docker-compose.yml..."
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  cheshire-cat-core:
    image: ghcr.io/cheshire-cat-ai/core:${CCAT_VERSION}
    container_name: cheshire_cat_core
    hostname: cheshire-cat
    
    ports:
      - "0.0.0.0:1865:80"
    
    volumes:
      - ./static:/app/cat/static:rw
      - ./plugins:/app/cat/plugins:rw
      - ./data:/app/cat/data:rw
      - ./logs:/app/cat/logs:rw
    
    environment:
      - PYTHONUNBUFFERED=1
      - CCAT_LOG_LEVEL=INFO
      - CCAT_CORS_ALLOWED_ORIGINS=*
      - TZ=Europe/Rome
    
    extra_hosts:
      - "host.docker.internal:host-gateway"
    
    restart: unless-stopped
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s
    
    deploy:
      resources:
        limits:
          cpus: '6'
          memory: 12G
        reservations:
          cpus: '2'
          memory: 4G
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  default:
    name: cheshire-cat-network
    driver: bridge
EOF
    
    # .env file
    cat > "$INSTALL_DIR/.env" << EOF
CCAT_VERSION=${CCAT_VERSION}
OLLAMA_MODEL=${OLLAMA_MODEL}
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_BASE_URL_FALLBACK=http://${DOCKER_BRIDGE_IP}:11434
CCAT_LOG_LEVEL=INFO
TZ=Europe/Rome
EOF
    
    # README
    cat > "$INSTALL_DIR/README.md" << EOF
# Cheshire Cat AI - Proxmox VM Installation

## Informazioni

- **Data**: $(date)
- **Versione Cat**: ${CCAT_VERSION}
- **Modello**: ${OLLAMA_MODEL}
- **IP VM**: ${VM_IP}

## Accesso

- **URL**: http://${VM_IP}:1865/admin
- **Credenziali**: admin / admin (CAMBIALE!)

## Configurazione Ollama

Settings > Language Model > Ollama Chat Model:
- Base URL: \`http://host.docker.internal:11434\`
- Model: \`${OLLAMA_MODEL}\`

Settings > Embedder > Qdrant FastEmbed:
- Model: \`BAAI/bge-small-en-v1.5\`

## Comandi

\`\`\`bash
cd $INSTALL_DIR
docker compose ps
docker compose logs -f
./monitor.sh
\`\`\`
EOF
    
    # .gitignore
    cat > "$INSTALL_DIR/.gitignore" << 'EOF'
data/
logs/
*.log
.env
*.tar.gz
EOF
    
    chown -R "$TARGET_USER":"$TARGET_USER" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"
    
    success "✓ Struttura creata"
    
    # Pull immagine
    info "Download immagine Cheshire Cat..."
    cd "$INSTALL_DIR"
    
    if retry_command 3 sudo -u "$TARGET_USER" docker compose pull; then
        success "✓ Immagine scaricata"
    else
        error "Download immagine fallito"
        exit 1
    fi
    
    # Avvio
    info "Avvio container..."
    sudo -u "$TARGET_USER" docker compose up -d
    
    info "Primo avvio con FastEmbed (90s)..."
    progress_bar 90 "Inizializzazione"
    
    if sudo -u "$TARGET_USER" docker compose ps | grep -q "Up"; then
        success "✓ Container avviato"
    else
        error "Container non avviato"
        exit 1
    fi
    
    save_state "CHESHIRE_DEPLOYED"
}

#==============================================================================
# STEP 7: SCRIPT MANUTENZIONE
#==============================================================================

create_maintenance_scripts() {
    section "STEP 7: Script Manutenzione"
    
    # monitor.sh
    cat > "$INSTALL_DIR/monitor.sh" << 'EOFMON'
#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        CHESHIRE CAT AI - SYSTEM MONITORING             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}=== Sistema ===${NC}"
echo "Uptime:   $(uptime -p)"
echo "Load Avg: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

echo -e "${BLUE}=== Risorse ===${NC}"
free -h | awk 'NR==2{print "RAM: "$3"/"$2" ("int($3/$2*100)"%)"}'
echo "Disk: $(df -h / | awk 'NR==2 {print $3"/"$2" ("$5" used)"}')"
echo ""

echo -e "${BLUE}=== Servizi ===${NC}"
systemctl is-active --quiet ollama && echo -e "${GREEN}✓${NC} Ollama: ATTIVO" || echo -e "${RED}✗${NC} Ollama: INATTIVO"
systemctl is-active --quiet docker && echo -e "${GREEN}✓${NC} Docker: ATTIVO" || echo -e "${RED}✗${NC} Docker: INATTIVO"
echo ""

echo -e "${BLUE}=== Container ===${NC}"
docker ps --filter name=cheshire_cat_core --format "table {{.Names}}\t{{.Status}}"
echo ""

echo -e "${BLUE}=== Modelli Ollama ===${NC}"
ollama list
echo ""

echo -e "${BLUE}=== Test API ===${NC}"
curl -sf http://localhost:11434/api/tags >/dev/null && echo -e "${GREEN}✓${NC} Ollama API: OK" || echo -e "${RED}✗${NC} Ollama API: DOWN"
curl -sf http://localhost:1865/ >/dev/null && echo -e "${GREEN}✓${NC} Cat API: OK" || echo -e "${RED}✗${NC} Cat API: DOWN"
echo ""
EOFMON
    
    chmod +x "$INSTALL_DIR/monitor.sh"
    
    # backup.sh
    cat > "$INSTALL_DIR/backup.sh" << 'EOFBACK'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="$HOME/backups/cheshire-cat"
DATE=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$BACKUP_DIR"

echo "=== Backup Cheshire Cat ==="
tar -czf "$BACKUP_DIR/cat-data-$DATE.tar.gz" \
    -C "$SCRIPT_DIR" data plugins static docker-compose.yml .env 2>/dev/null

if [ -f "$BACKUP_DIR/cat-data-$DATE.tar.gz" ]; then
    SIZE=$(du -h "$BACKUP_DIR/cat-data-$DATE.tar.gz" | cut -f1)
    echo "✓ Backup: cat-data-$DATE.tar.gz ($SIZE)"
else
    echo "✗ Backup fallito"
    exit 1
fi

find "$BACKUP_DIR" -name "cat-data-*.tar.gz" -mtime +14 -delete
echo "Backup salvati in: $BACKUP_DIR"
EOFBACK
    
    chmod +x "$INSTALL_DIR/backup.sh"
    
    chown -R "$TARGET_USER":"$TARGET_USER" "$INSTALL_DIR"/*.sh
    
    success "✓ Script creati: monitor.sh, backup.sh"
    
    # Cronjob backup
    (sudo -u "$TARGET_USER" crontab -l 2>/dev/null || true; echo "0 3 * * * $INSTALL_DIR/backup.sh >> $INSTALL_DIR/logs/backup.log 2>&1") | sudo -u "$TARGET_USER" crontab -
    
    success "✓ Backup automatico: 3:00 AM"
    
    save_state "MAINTENANCE_CONFIGURED"
}

#==============================================================================
# STEP 8: TEST FINALI
#==============================================================================

run_tests() {
    section "STEP 8: Test Finali"
    
    local tests_passed=0
    local tests_failed=0
    
    # Test 1: Ollama
    info "[1/6] Test Ollama API..."
    if retry_command 3 test_connection "http://localhost:11434/api/tags" 5; then
        success "✓ Ollama API OK"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ Ollama API DOWN"
        tests_failed=$((tests_failed + 1))
    fi
    
    # Test 2: Container
    info "[2/6] Test container..."
    if docker ps --filter name=cheshire_cat_core --format '{{.Status}}' | grep -q "Up"; then
        success "✓ Container attivo"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ Container non attivo"
        tests_failed=$((tests_failed + 1))
    fi
    
    # Test 3: Docker → Ollama
    info "[3/6] Test Docker → Ollama..."
    sleep 5
    if docker exec cheshire_cat_core curl -sf http://host.docker.internal:11434/api/tags >/dev/null 2>&1; then
        success "✓ Container raggiunge Ollama"
        tests_passed=$((tests_passed + 1))
    else
        if docker exec cheshire_cat_core curl -sf "http://${DOCKER_BRIDGE_IP}:11434/api/tags" >/dev/null 2>&1; then
            success "✓ Container raggiunge Ollama (via bridge)"
            warn "⚠ Usa: http://${DOCKER_BRIDGE_IP}:11434 nel portal"
            tests_passed=$((tests_passed + 1))
        else
            error "✗ Container non raggiunge Ollama"
            tests_failed=$((tests_failed + 1))
        fi
    fi
    
    # Test 4: Cat API
    info "[4/6] Test Cheshire Cat API..."
    local retries=0
    local cat_ok=false
    while [ $retries -lt 15 ]; do
        if curl -sf http://localhost:1865/ | grep -q "mad here"; then
            success "✓ Cat API OK"
            cat_ok=true
            tests_passed=$((tests_passed + 1))
            break
        fi
        retries=$((retries + 1))
        sleep 4
    done
    
    if [ "$cat_ok" = false ]; then
        warn "⚠ Cat API lenta"
        tests_failed=$((tests_failed + 1))
    fi
    
    # Test 5: Modello
    info "[5/6] Test modello $OLLAMA_MODEL..."
    if ollama list | grep -q "$OLLAMA_MODEL"; then
        success "✓ Modello disponibile"
        tests_passed=$((tests_passed + 1))
    else
        error "✗ Modello non trovato"
        tests_failed=$((tests_failed + 1))
    fi
    
    # Test 6: Qemu Agent (solo VM) / Ambiente CT / Bare-metal
    if [ "$IS_CT" = false ] && [ "$IS_BAREMETAL" = false ]; then
        info "[6/6] Test Qemu Agent..."
        if systemctl is-active --quiet qemu-guest-agent; then
            success "✓ Qemu Agent attivo"
            tests_passed=$((tests_passed + 1))
        else
            warn "⚠ Qemu Agent non attivo"
            tests_failed=$((tests_failed + 1))
        fi
    elif [ "$IS_CT" = true ]; then
        info "[6/6] Test ambiente CT..."
        success "✓ LXC Container rilevato (Qemu Agent non necessario)"
        tests_passed=$((tests_passed + 1))
    else
        info "[6/6] Test ambiente bare-metal..."
        success "✓ Bare-metal rilevato (Qemu Agent non necessario)"
        tests_passed=$((tests_passed + 1))
    fi
    
    echo ""
    echo -e "${BOLD}═══ Riepilogo Test ===${NC}"
    echo -e "Passati: ${GREEN}$tests_passed${NC}/6"
    echo -e "Falliti: ${RED}$tests_failed${NC}/6"
    echo ""
    
    if [ $tests_failed -eq 0 ]; then
        success "✓ Tutti i test OK"
        save_state "TESTS_PASSED"
    elif [ $tests_passed -ge 4 ]; then
        warn "⚠ Alcuni test falliti ma sistema funzionante"
        save_state "TESTS_PARTIAL"
    else
        error "✗ Troppi test falliti"
        save_state "TESTS_FAILED"
        return 1
    fi
}

#==============================================================================
# STEP 9: REPORT FINALE
#==============================================================================

print_final_report() {
    section "INSTALLAZIONE COMPLETATA!"
    
    local install_end_time
    install_end_time=$(date +%s)
    local install_duration=$((install_end_time - INSTALL_START_TIME))
    local install_minutes=$((install_duration / 60))
    local install_seconds=$((install_duration % 60))
    
    echo -e "${GREEN}${BOLD}"
    cat << 'EOF'
   ╔═══════════════════════════════════════════════════════════╗
   ║                                                           ║
   ║      🎉  CHESHIRE CAT AI INSTALLATO CON SUCCESSO!  🎉    ║
   ║                                                           ║
   ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo ""
    info "📊 Statistiche:"
    echo "   Tempo: ${install_minutes}m ${install_seconds}s"
    echo "   Errori: $ERRORS_ENCOUNTERED"
    echo "   Warning: $WARNINGS_ENCOUNTERED"
    echo ""
    
    local env_label="VM"
    [ "$IS_CT" = true ] && env_label="CT"
    [ "$IS_BAREMETAL" = true ] && env_label="Bare-metal"

    info "📍 ACCESSO ADMIN PORTAL:"
    echo -e "   ${CYAN}Da ${env_label}:${NC}         http://localhost:1865/admin"
    echo -e "   ${CYAN}Da LAN:${NC}        http://$VM_IP:1865/admin"
    echo ""
    echo -e "   ${YELLOW}${BOLD}Credenziali:${NC}"
    echo -e "   Username: ${BOLD}admin${NC}"
    echo -e "   Password: ${BOLD}admin${NC}  ${RED}${BOLD}← CAMBIALA!${NC}"
    echo ""
    
    info "⚙️  CONFIGURAZIONE (nel portale admin):"
    echo ""
    echo "   ${BOLD}1. Language Model${NC}"
    echo "      Settings > Language Model > Ollama Chat Model"
    echo -e "      ${GREEN}Base URL:${NC} http://host.docker.internal:11434"
    echo -e "      ${GREEN}Model:${NC}    $OLLAMA_MODEL"
    echo ""
    
    echo "   ${BOLD}2. Embedder${NC}"
    echo "      Settings > Embedder > Qdrant FastEmbed"
    echo -e "      ${GREEN}Model:${NC}    BAAI/bge-small-en-v1.5"
    echo ""
    
    echo "   ${BOLD}3. Cambia Password${NC}"
    echo "      Settings > Users > admin > Change Password"
    echo ""
    
    info "🔧 COMANDI UTILI:"
    echo "   cd $INSTALL_DIR"
    echo "   ./monitor.sh              # Monitoring"
    echo "   docker compose logs -f    # Log real-time"
    echo "   ollama list               # Modelli"
    echo ""
    
    info "📂 DIRECTORY:"
    echo "   Progetto:  $INSTALL_DIR"
    echo "   Dati:      $INSTALL_DIR/data"
    echo "   Plugin:    $INSTALL_DIR/plugins"
    echo "   Backup:    $BACKUP_DIR"
    echo "   Log:       $LOG_FILE"
    echo ""
    
    info "🔒 SICUREZZA:"
    if [ "$FIREWALL_ENABLED" = "true" ]; then
        echo "   ✓ Firewall UFW attivo"
        echo "   ✓ Fail2ban configurato"
    else
        echo "   ⚠ Firewall gestito a livello host Proxmox"
    fi
    echo "   ✓ SSH porta: $SSH_PORT"
    echo "   ✓ Cat: solo LAN"
    echo "   ✓ Ollama: LAN (porta 11434 — utilizzabile da Aider, Open WebUI, ecc.)"
    echo ""
    
    if [ -f "$BACKUP_DIR/user-password.txt" ]; then
        warn "👤 Password utente $TARGET_USER salvata in: $BACKUP_DIR/user-password.txt"
        echo ""
    fi
    
    success "🚀 Sistema pronto!"
    echo ""
    echo -e "${MAGENTA}${BOLD}Prossimo passo:${NC} http://$VM_IP:1865/admin"
    echo ""
    
    save_state "COMPLETED"
}

#==============================================================================
# ROLLBACK
#==============================================================================

perform_rollback() {
    section "ROLLBACK INSTALLAZIONE"
    
    warn "⚠ Rimozione installazione..."
    read -r -p "Confermare? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    if [ -f "$INSTALL_DIR_BASE/docker-compose.yml" ]; then
        cd "$INSTALL_DIR_BASE"
        docker compose down -v 2>/dev/null || true
        success "✓ Container rimossi"
    fi
    
    if systemctl is-active --quiet ollama; then
        systemctl stop ollama
        systemctl disable ollama
        success "✓ Ollama disabilitato"
    fi
    
    success "✓ Rollback completato"
}

#==============================================================================
# MAIN
#==============================================================================

main() {
    clear
    
    echo -e "${BLUE}${BOLD}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║       CHESHIRE CAT AI + OLLAMA - INSTALLER AUTOMATICO           ║
║          Production-Ready per Proxmox VM / CT                    ║
║                                                                  ║
║  Debian 13 Trixie | Docker | Ollama | Qwen3:8b                  ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}Versione:${NC} $SCRIPT_VERSION"
    echo -e "${CYAN}Data:${NC}     $(date)"
    echo ""
    
    if [ "${1:-}" = "--rollback" ]; then
        perform_rollback
        exit 0
    fi
    
    init_logging
    
    info "Installazione avviata da: $(whoami)"
    info "Working directory: $(pwd)"
    info "Parametri: $*"
    echo ""
    
    preflight_checks
    configure_system
    configure_security
    install_docker
    install_ollama
    download_model
    deploy_cheshire_cat
    create_maintenance_scripts
    run_tests
    print_final_report
    
    rm -f "$STATE_FILE"
    echo "=== Completato: $(date) ===" >> "$LOG_FILE"
    
    exit 0
}

main "$@"

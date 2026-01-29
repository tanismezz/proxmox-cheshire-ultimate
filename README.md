# Cheshire Cat AI + Ollama - Installer Automatico Proxmox VM

Script di installazione automatica per [Cheshire Cat AI](https://cheshirecat.ai/) con [Ollama](https://ollama.com/) su VM Proxmox con Debian 13 Trixie.

Installa e configura in un solo comando: Docker, Ollama, il modello LLM Qwen3:8b, Cheshire Cat, firewall UFW, Fail2ban, backup automatici e script di monitoraggio.

## Requisiti minimi VM

| Risorsa | Minimo |
|---------|--------|
| CPU | 4 cores |
| RAM | 12 GB |
| Disco | 32 GB |
| OS | Debian 13 Trixie |
| Rete | Connessione internet |
| Proxmox | Qemu Guest Agent abilitato |

## Installazione

```bash
git clone https://github.com/tanismezz/proxmox-cheshire-ultimate.git
sudo bash proxmox-cheshire-ultimate/proxmox-cheshire-ultimate.sh
```

Lo script esegue automaticamente:

1. **Pre-flight checks** - Verifica requisiti (RAM, disco, rete, kernel)
2. **Sistema base** - Aggiornamento pacchetti, utility, ottimizzazione kernel
3. **Sicurezza** - Firewall UFW, Fail2ban, hardening
4. **Docker Engine** - Installazione ufficiale con Docker Compose
5. **Ollama** - Installazione nativa con binding su tutte le interfacce
6. **Modello LLM** - Download Qwen3:8b (~6GB)
7. **Cheshire Cat** - Deploy container Docker v1.9.1
8. **Manutenzione** - Script monitor, backup automatico (cron 3:00 AM)
9. **Test finali** - Verifica tutti i servizi

## Configurazione post-installazione

Apri nel browser: `http://<IP-DELLA-VM>:1865/admin`

Credenziali default: `admin` / `admin` (**cambiala subito!**)

### Language Model

Settings > Language Model > **Ollama Chat Model**

| Campo | Valore |
|-------|--------|
| Base URL | `http://host.docker.internal:11434` |
| Model | `qwen3:8b` |

### Embedder

Settings > Embedder > **Qdrant FastEmbed**

| Campo | Valore |
|-------|--------|
| Model | `BAAI/bge-small-en-v1.5` |

## Comandi utili

```bash
cd ~/cheshire-cat-ai

# Monitoraggio sistema
./monitor.sh

# Log in tempo reale
docker compose logs -f

# Stato container
docker compose ps

# Modelli Ollama installati
ollama list

# Backup manuale
./backup.sh
```

## Rollback

Per disinstallare:

```bash
sudo bash proxmox-cheshire-ultimate/proxmox-cheshire-ultimate.sh --rollback
```

## Struttura directory

```
~/cheshire-cat-ai/
├── docker-compose.yml
├── .env
├── monitor.sh
├── backup.sh
├── data/           # Dati persistenti
├── plugins/        # Plugin Cheshire Cat
├── static/         # File statici
└── logs/           # Log applicazione
```

## Sicurezza

- Firewall UFW attivo (porta 1865 solo LAN, Ollama solo localhost + Docker)
- Fail2ban configurato (SSH max 3 tentativi, ban 2 ore)
- Backup automatico giornaliero alle 3:00 AM

## Licenza

MIT

# Cheshire Cat AI + Ollama - Installer Automatico Proxmox VM / CT / Bare-metal

Script di installazione automatica per [Cheshire Cat AI](https://cheshirecat.ai/) con [Ollama](https://ollama.com/) su Debian 13 Trixie.

Compatibile con **VM Proxmox**, **Container LXC (CT)** e **server Debian bare-metal**.

Installa e configura in un solo comando: Docker, Ollama, il modello LLM Qwen3:8b, Cheshire Cat, firewall UFW, Fail2ban, backup automatici e script di monitoraggio.

## Requisiti minimi

| Risorsa | Minimo |
|---------|--------|
| CPU | 4 cores |
| RAM | 12 GB |
| Disco | 32 GB |
| OS | Debian 13 Trixie |
| Rete | Connessione internet |

> In VM Proxmox si consiglia di abilitare il Qemu Guest Agent nelle opzioni della VM.
> In CT e bare-metal il Qemu Guest Agent viene automaticamente saltato.

## Ambienti supportati

| Ambiente | Rilevamento | Note |
|----------|-------------|------|
| VM Proxmox (KVM/QEMU) | `systemd-detect-virt` = `kvm` | Installa qemu-guest-agent, sysctl completo |
| CT LXC Proxmox | `systemd-detect-virt` = `lxc` | Skip qemu-agent, sysctl parziale (read-only), fallback timezone |
| Debian bare-metal | `systemd-detect-virt` = `none` | Skip qemu-agent, sysctl completo, funzionamento nativo |

Lo script rileva automaticamente l'ambiente e si adatta senza intervento manuale.

## Installazione

```bash
# Installa git (se non presente)
sudo apt-get update && sudo apt-get install -y git

# Clona il repository e lancia lo script
git clone https://github.com/tanismezz/proxmox-cheshire-ultimate.git
cd proxmox-cheshire-ultimate
sudo bash proxmox-cheshire-ultimate.sh
```

## Cosa fa lo script

Lo script esegue automaticamente 9 step:

| Step | Descrizione |
|------|-------------|
| 0 | **Pre-flight checks** - Verifica requisiti (RAM, disco, rete, kernel, tipo ambiente) |
| 1 | **Sistema base** - Aggiornamento pacchetti, utility, qemu-agent (solo VM), ottimizzazione kernel |
| 2 | **Sicurezza** - Firewall UFW, Fail2ban, porte LAN per Cat e Ollama |
| 3 | **Docker Engine** - Installazione ufficiale con Docker Compose v2 |
| 4 | **Ollama** - Installazione nativa con binding su tutte le interfacce |
| 5 | **Modello LLM** - Download Qwen3:8b (~6GB) |
| 6 | **Cheshire Cat** - Deploy container Docker v1.9.1 |
| 7 | **Manutenzione** - Script monitor.sh, backup.sh, cron automatico alle 3:00 AM |
| 8 | **Test finali** - 6 test automatici su tutti i servizi |
| 9 | **Report** - Riepilogo con URL, credenziali e istruzioni |

## Configurazione post-installazione

Apri nel browser: `http://<IP-DELLA-MACCHINA>:1865/admin`

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

> **Per uso in italiano**: si consiglia `intfloat/multilingual-e5-large` come embedder.
> Supporta italiano, inglese e altre 90+ lingue con qualita nettamente superiore rispetto a `bge-small-en` per testi non inglesi.
>
> Per impostarlo: Settings > Embedder > **Qdrant FastEmbed** > Model: `intfloat/multilingual-e5-large`
>
> Richiede ~1.2 GB extra di RAM rispetto a bge-small-en.

## Modelli LLM disponibili

Lo script installa di default `qwen3:8b`. Per usare un modello diverso:

```bash
# Scarica un nuovo modello
ollama pull <nome-modello>

# Vedi i modelli installati
ollama list

# Rimuovi un modello che non usi piu
ollama rm qwen3:8b
```

Vedi tutti i modelli disponibili su [ollama.com/library](https://ollama.com/library)

### Modelli general-purpose

| Modello | RAM minima | Descrizione |
|---------|-----------|-------------|
| `qwen3:8b` | 12 GB | **Default**, ottimo bilanciamento (multilingua, thinking mode) |
| `llama3.1:8b` | 12 GB | Meta, ottime prestazioni generali |
| `mistral:7b` | 10 GB | Veloce, buono per chat |
| `gemma2:9b` | 12 GB | Google, buona qualita |
| `qwen3:4b` | 6 GB | Leggero, per macchine con poca RAM |
| `llama3.1:70b` | 48 GB | Qualita top, richiede molta RAM |

### Modelli per coding

| Modello | RAM minima | Descrizione |
|---------|-----------|-------------|
| `qwen2.5-coder:7b` | 10 GB | Ottimo per codice, supporta 90+ linguaggi |
| `codellama:7b` | 10 GB | Meta, specializzato per codice e completamento |
| `deepseek-coder-v2:16b` | 20 GB | Molto forte su codice e ragionamento |
| `starcoder2:7b` | 10 GB | BigCode, addestrato su The Stack v2 |
| `codegemma:7b` | 10 GB | Google, buono per generazione e spiegazione codice |
| `qwen2.5-coder:32b` | 24 GB | Qualita top coding, richiede piu RAM |

> **Tip per Aider**: Ollama e raggiungibile da tutta la LAN sulla porta 11434.
> Da un'altra macchina in rete puoi usare:
> ```
> export OLLAMA_API_BASE=http://<IP-DELLA-MACCHINA>:11434
> aider --model ollama/qwen2.5-coder:7b
> ```

Dopo aver scaricato il nuovo modello, aggiorna la configurazione in Cheshire Cat:

1. Apri `http://<IP-DELLA-MACCHINA>:1865/admin`
2. Vai in **Settings > Language Model > Ollama Chat Model**
3. Cambia il campo **Model** con il nome del nuovo modello
4. Salva

## Rete e porte

| Porta | Servizio | Accesso |
|-------|----------|---------|
| 22 (SSH) | SSH | Ovunque |
| 1865 | Cheshire Cat (web UI + API) | Solo LAN |
| 11434 | Ollama API | Solo LAN |

Ollama e accessibile da qualsiasi macchina nella stessa rete locale. Questo permette di usarlo con client esterni come **Aider**, **Open WebUI**, **Continue** (VS Code), ecc.

La porta e bloccata da internet tramite UFW (DENY WAN).

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

# Test Ollama API
curl http://localhost:11434/api/tags

# Test Cheshire Cat API
curl http://localhost:1865/
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
├── README.md
├── data/           # Dati persistenti (Qdrant, memoria)
├── plugins/        # Plugin Cheshire Cat
├── static/         # File statici
└── logs/           # Log applicazione
```

## Sicurezza

- Firewall UFW attivo (Cat e Ollama solo LAN, bloccati da WAN)
- Fail2ban configurato (SSH max 3 tentativi, ban 2 ore)
- Backup automatico giornaliero alle 3:00 AM
- Docker con log rotation (10MB x 3 file)
- Kernel ottimizzato per workload AI

## Licenza

MIT

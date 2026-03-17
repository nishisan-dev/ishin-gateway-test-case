# Lab 1 — Cluster ishin-gateway com Observabilidade Completa

Laboratório Vagrant que provisiona um cluster ishin-gateway de dois nós com proxy reverso, dashboard de observabilidade embutido, e distributed tracing via Zipkin com storage persistente em Elasticsearch.

## Objetivo

Validar o funcionamento end-to-end do ishin-gateway em cenário de cluster, incluindo:

- **Proxy reverso** com load balancing para backend Nginx
- **Cluster NGrid** com replicação de estado e deploy de rules distribuído
- **Dashboard de observabilidade** com métricas, topologia e traces
- **Distributed tracing** com Brave/Zipkin exportando spans para Elasticsearch
- **Admin API + CLI** para gestão de rules em cluster

## Topologia

![Topologia do Lab](https://uml.nishisan.dev/proxy?src=https://raw.githubusercontent.com/nishisan-dev/ishin-gateway-test-case/main/docs/diagrams/lab_topology.puml)

### Rede privada

Todas as VMs estão conectadas via rede privada `192.168.56.0/24` no VirtualBox/libvirt, com resolução de nomes configurada via `/etc/hosts`.

| VM | IP | Função |
| --- | --- | --- |
| `ishin-1` | `192.168.56.11` | Nó proxy + dashboard + cluster |
| `ishin-2` | `192.168.56.12` | Nó proxy + dashboard + cluster |
| `web-1` | `192.168.56.21` | Backend Nginx |
| `zipkin-1` | `192.168.56.31` | Elasticsearch + Zipkin Server |

### Fluxos de dados

```
                   ┌──────────────┐
                   │   Cliente    │
                   └──────┬───────┘
                          │ HTTP :19090 / :29090
                   ┌──────▼───────┐
              ┌────┤   ishin-gateway     ├────┐
              │    │  (cluster)   │    │
              │    └──────────────┘    │
              │                        │
     ┌────────▼────────┐    ┌─────────▼────────┐
     │    ishin-1      │◄──►│    ishin-2       │  NGrid :7100
     │  proxy + dash   │    │  proxy + dash    │  (replicação)
     └────────┬────────┘    └─────────┬────────┘
              │                        │
              │    upstream :80        │
              └────────┬───────────────┘
                       │
              ┌────────▼────────┐
              │     web-1       │
              │    (Nginx)      │
              └─────────────────┘

     ishin-1 ──spans──►┐
                        │   Brave/Zipkin
     ishin-2 ──spans──►─┤   :9411
                        │
              ┌─────────▼───────┐
              │    zipkin-1     │
              │  ES + Zipkin    │
              └─────────────────┘
```

## Recursos necessários

| VM | vCPUs | RAM | Disco | Serviços |
| --- | --- | --- | --- | --- |
| `ishin-1` | 2 | 2 GB | ~2 GB | ishin-gateway (JVM), H2 embedded |
| `ishin-2` | 2 | 2 GB | ~2 GB | ishin-gateway (JVM), H2 embedded |
| `web-1` | 2 | 1 GB | ~1 GB | Nginx |
| `zipkin-1` | 2 | 3 GB | ~5 GB | Elasticsearch (JVM), Zipkin (JVM) |
| **Total** | **8** | **8 GB** | **~10 GB** | |

> O host precisa de no mínimo **10 GB de RAM livre** (8 GB para VMs + overhead do hypervisor) e **~15 GB de disco** para box images + dados.

## Pré-requisitos

- **Vagrant** ≥ 2.3
- **Provider**: `libvirt` com `vagrant-libvirt` (default) ou `VirtualBox`
- **Conexão com internet** (para download dos pacotes .deb, Elasticsearch, e Zipkin JAR)

## Como subir

### Usando o script (recomendado)

```bash
./start.sh
```

O script sobe as VMs na ordem correta e exibe um resumo consolidado com todas as URLs ao final.

Para subir VMs específicas:

```bash
./start.sh web-1 zipkin-1
```

### Manualmente

A ordem importa para o bootstrap do cluster:

```bash
vagrant up web-1       # backend primeiro
vagrant up zipkin-1    # tracing antes dos proxies
vagrant up ishin-1     # primeiro nó do cluster
vagrant up ishin-2     # segundo nó se conecta ao primeiro
```

> O provider default é `libvirt`. Para VirtualBox: `VAGRANT_DEFAULT_PROVIDER=virtualbox vagrant up`

## Portas e acessos

### Port forwarding (host → guest)

| Serviço | VM | Porta guest | Porta host | URL do host |
| --- | --- | --- | --- | --- |
| Proxy | `ishin-1` | 9090 | 19090 | http://localhost:19090 |
| Proxy | `ishin-2` | 9090 | 29090 | http://localhost:29090 |
| Management API | `ishin-1` | 9190 | 19190 | http://localhost:19190 |
| Management API | `ishin-2` | 9190 | 29190 | http://localhost:29190 |
| Dashboard | `ishin-1` | 9200 | 19200 | http://localhost:19200 |
| Dashboard | `ishin-2` | 9200 | 29200 | http://localhost:29200 |
| Nginx | `web-1` | 80 | 18080 | http://localhost:18080 |
| Zipkin UI | `zipkin-1` | 9411 | 39411 | http://localhost:39411 |

### Portas internas (rede privada)

| Porta | Protocolo | Função |
| --- | --- | --- |
| 7100 | TCP | NGrid cluster (mesh de replicação) |
| 9200 | HTTP | Elasticsearch (bind em localhost na zipkin-1) |

## Componentes em detalhe

### ishin-gateway (ishin-1, ishin-2)

Cada nó roda o ishin-gateway `v3.1.2` instalado via pacote `.deb` do GitHub Releases.

**Configuração do proxy (`/etc/ishin-gateway/adapter.yaml`):**

- Listener HTTP em `:9090` sem SSL/auth
- Backend apontando para `web-1:80`
- Rule pass-through (`default/Rules.groovy` — forwards tudo)
- Pool: 128 conexões, 256 requests max, keepalive 5min

**Cluster NGrid:**

- Habilitado com `replicationFactor: 2`
- Seeds cruzados: `ishin-1` → `ishin-2:7100` e vice-versa
- Dados em `/var/log/ishin-gateway/ngrid-data`

**Dashboard de Observabilidade:**

- Habilitado em `:9200`, bind `0.0.0.0`
- Storage H2 em `/var/lib/ishin-gateway`, retenção de 24h, scrape a cada 15s
- Proxy Zipkin habilitado, apontando para `http://zipkin-1:9411`
- Allowlist: `127.0.0.1`, `::1`, `10.0.0.0/8`, `192.168.0.0/16`

**Tracing (Brave → Zipkin):**

- `ZIPKIN_ENDPOINT=http://zipkin-1:9411/api/v2/spans` via systemd override
- Sampling: 100% (ALWAYS_SAMPLE) — adequado para lab
- Instance ID resolvido via hostname (`ishin-1`, `ishin-2`)

**Admin API:**

- Habilitada no management port `:9190`
- API Key: `nishisan`

**Systemd:**

- Unit: `ishin-gateway.service` com override em `/etc/systemd/system/ishin-gateway.service.d/override.conf`
- ReadWritePaths: `/var/log/ishin-gateway`, `/var/lib/ishin-gateway`

### Nginx (web-1)

Backend simples que serve uma página HTML estática e um endpoint `/health`.

- Porta: `80`
- Root: `/var/www/html`
- Health check: `GET /health` → `200 ok`

### Elasticsearch (zipkin-1)

Elasticsearch 8.x rodando em single-node mode com recursos estritamente limitados.

**Contenção de recursos:**

| Parâmetro | Valor | Justificativa |
| --- | --- | --- |
| JVM Heap | 512 MB | Mínimo funcional para ES |
| `discovery.type` | `single-node` | Sem overhead de cluster |
| `xpack.ml.enabled` | `false` | ML consome muita RAM |
| `xpack.watcher.enabled` | `false` | Desnecessário para lab |
| `xpack.monitoring.collection.enabled` | `false` | Reduz I/O |
| `xpack.security.*` | `false` | Sem overhead de TLS/auth |
| `network.host` | `127.0.0.1` | Bind apenas localhost |

**Proteção contra disco cheio (watermarks):**

| Watermark | Threshold | Ação |
| --- | --- | --- |
| Low | 85% | Para de alocar novos shards |
| High | 90% | Realoca shards para liberar espaço |
| Flood stage | 95% | Índices ficam read-only |

**Retenção automática:**

- Systemd timer `zipkin-cleanup.timer` executa diariamente às 03:00
- Script `/usr/local/bin/zipkin-index-cleanup.sh` deleta índices `zipkin-*` com mais de **1 dia**
- Pode ser executado manualmente: `sudo /usr/local/bin/zipkin-index-cleanup.sh`
- Verificar status: `sudo systemctl list-timers zipkin-cleanup.timer`

### Zipkin Server (zipkin-1)

Zipkin rodando como JAR standalone com storage via Elasticsearch.

**Configuração:**

| Variável | Valor | Função |
| --- | --- | --- |
| `STORAGE_TYPE` | `elasticsearch` | Persistência em ES |
| `ES_HOSTS` | `http://127.0.0.1:9200` | Conexão local com ES |
| `ES_INDEX` | `zipkin` | Prefixo dos índices |
| `ES_INDEX_REPLICAS` | `0` | Sem réplicas (single-node) |
| `ES_INDEX_SHARDS` | `1` | Mínimo possível |

**JVM:** `-Xms128m -Xmx256m`

**Systemd:** `zipkin.service` com `Requires=elasticsearch.service` (ES sobe antes)

## Testes de validação

### 1. Verificar backend

```bash
curl http://localhost:18080
# Deve retornar: página HTML do Nginx
```

### 2. Verificar proxy

```bash
curl http://localhost:19090
curl http://localhost:29090
# Ambos devem retornar a mesma página do Nginx (proxied)
```

### 3. Verificar cluster

```bash
vagrant ssh ishin-1 -c "sudo journalctl -u ishin-gateway -n 50 --no-pager | grep -i cluster"
# Deve mostrar conexão com ishin-2
```

### 4. Verificar Zipkin

```bash
# Health check
curl http://localhost:39411/health

# UI (abrir no browser)
# http://localhost:39411

# Traces recentes (após gerar tráfego)
curl "http://localhost:39411/api/v2/traces?limit=5"
```

### 5. Verificar Dashboard

```bash
# Health dos dashboards
curl http://localhost:19200/api/dashboard/health
curl http://localhost:29200/api/dashboard/health

# Proxy de traces via Dashboard
curl http://localhost:19200/api/dashboard/traces
```

### 6. Verificar Elasticsearch

```bash
vagrant ssh zipkin-1 -c "curl -s http://127.0.0.1:9200/_cluster/health?pretty"
vagrant ssh zipkin-1 -c "curl -s http://127.0.0.1:9200/_cat/indices/zipkin-*?v"
```

### 7. Testar deploy de rules em cluster

```bash
# Via CLI (dentro da VM)
vagrant ssh ishin-1 -c "export ISHIN_API_KEY=nishisan && ishin-cli list"

# Via curl (do host)
curl http://localhost:19190/admin/rules/list -H "X-API-Key: nishisan"
curl http://localhost:29190/admin/rules/list -H "X-API-Key: nishisan"
```

## Operações comuns

### Acessar VMs

```bash
vagrant ssh ishin-1
vagrant ssh ishin-2
vagrant ssh web-1
vagrant ssh zipkin-1
```

### Ver logs

```bash
# ishin-gateway
vagrant ssh ishin-1 -c "sudo journalctl -u ishin-gateway -f"

# Zipkin
vagrant ssh zipkin-1 -c "sudo journalctl -u zipkin -f"

# Elasticsearch
vagrant ssh zipkin-1 -c "sudo journalctl -u elasticsearch -f"
```

### Ver status dos serviços

```bash
vagrant ssh ishin-1 -c "sudo systemctl status ishin-gateway --no-pager"
vagrant ssh zipkin-1 -c "sudo systemctl status elasticsearch zipkin --no-pager"
vagrant ssh web-1 -c "sudo systemctl status nginx --no-pager"
```

### Deploy ad-hoc (build local → VMs)

Para testar builds locais do ishin-gateway sem esperar release:

```bash
# Build e deploy em ambos os nós
../scripts/deploy_adhoc.sh

# Apenas em um nó
../scripts/deploy_adhoc.sh ishin-1

# Skip build, usar último JAR
../scripts/deploy_adhoc.sh --skip-build ishin-2
```

### Forçar cleanup do Elasticsearch

```bash
vagrant ssh zipkin-1 -c "sudo /usr/local/bin/zipkin-index-cleanup.sh"
```

### Verificar timer de cleanup

```bash
vagrant ssh zipkin-1 -c "sudo systemctl list-timers zipkin-cleanup.timer"
```

### Reprovisionar

```bash
vagrant provision              # todas
vagrant provision zipkin-1     # uma específica
```

### Destruir o lab

```bash
vagrant destroy -f
```

## Arquivos do projeto

```
ishin-gateway-test-case/
├── Vagrantfile                     # Definição das 4 VMs
├── start.sh                        # Script de boot com banner
├── README.md                       # Quick reference
├── docs/
│   ├── lab-1.md                    # Este documento
│   └── diagrams/
│       └── lab_topology.puml       # Diagrama PlantUML da topologia
└── scripts/
    ├── common.sh                   # Setup base (/etc/hosts, CA certs)
    ├── install_ishin.sh            # Provisioning dos nós ishin-gateway
    ├── install_nginx.sh            # Provisioning do backend Nginx
    └── install_zipkin.sh           # Provisioning do ES + Zipkin
```

## Troubleshooting

### VM não sobe

```bash
vagrant status                     # verificar estado
vagrant up <vm> --debug            # logs detalhados
```

### ishin-gateway não inicia

```bash
vagrant ssh ishin-1 -c "sudo journalctl -u ishin-gateway -n 100 --no-pager"
vagrant ssh ishin-1 -c "cat /etc/ishin-gateway/adapter.yaml"
vagrant ssh ishin-1 -c "cat /etc/systemd/system/ishin-gateway.service.d/override.conf"
```

### Zipkin não conecta no ES

```bash
vagrant ssh zipkin-1 -c "curl -s http://127.0.0.1:9200/_cluster/health?pretty"
vagrant ssh zipkin-1 -c "sudo journalctl -u elasticsearch -n 50 --no-pager"
vagrant ssh zipkin-1 -c "sudo journalctl -u zipkin -n 50 --no-pager"
```

### Traces não aparecem

1. Verificar se tráfego foi gerado: `curl http://localhost:19090`
2. Verificar se `ZIPKIN_ENDPOINT` está configurado: `vagrant ssh ishin-1 -c "cat /etc/systemd/system/ishin-gateway.service.d/override.conf"`
3. Verificar se Zipkin recebe spans: `vagrant ssh zipkin-1 -c "sudo journalctl -u zipkin -n 20 --no-pager"`
4. Verificar índices no ES: `vagrant ssh zipkin-1 -c "curl -s http://127.0.0.1:9200/_cat/indices/zipkin-*?v"`

### Disco cheio na zipkin-1

```bash
# Verificar uso de disco
vagrant ssh zipkin-1 -c "df -h"

# Verificar tamanho dos índices
vagrant ssh zipkin-1 -c "curl -s http://127.0.0.1:9200/_cat/indices/zipkin-*?v&s=store.size:desc"

# Forçar cleanup
vagrant ssh zipkin-1 -c "sudo /usr/local/bin/zipkin-index-cleanup.sh"
```

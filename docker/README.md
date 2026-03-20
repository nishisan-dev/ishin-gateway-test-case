# Laboratório Docker Compose para ishin-gateway

Versão containerizada do lab Vagrant — mesma topologia, fração dos recursos.

## Requisitos

- Docker Engine 24+
- Docker Compose v2

### Recursos

| Container | Imagem | RAM ~aprox | Papel |
| --- | --- | --- | --- |
| `tunnel-1` | `lnishisan/ishin-gateway:latest` | ~384 MB | Tunnel L4 LB + Dashboard + Cluster |
| `ishin-1` | `lnishisan/ishin-gateway:latest` | ~384 MB | Proxy + Dashboard + Cluster |
| `ishin-2` | `lnishisan/ishin-gateway:latest` | ~384 MB | Proxy + Dashboard + Cluster |
| `web-1` | `nginx:alpine` | ~16 MB | Nginx backend |
| `zipkin-1` | `openzipkin/zipkin:3.5` | ~256 MB | Distributed Tracing (in-memory) |
| **Total** | | **~1.4 GB** | |

> Comparado com ~10 GB do Vagrant (5 VMs com Ubuntu completo + Elasticsearch).

## Topologia

![Topologia Docker Lab](https://uml.nishisan.dev/proxy?src=https://raw.githubusercontent.com/nishisan-dev/ishin-gateway-test-case/main/docs/diagrams/docker_lab_topology.puml)

## Subir o ambiente

### Via script (recomendado)

```bash
cd docker/
./start.sh
```

O script sobe todos os containers, aguarda os health checks e exibe um banner com todos os endpoints.

### Manualmente

```bash
cd docker/
docker compose up -d
```

### Profiles de Load Balancing

O tunnel suporta dois algoritmos via Docker Compose profiles:

| Comando | Algoritmo | Config |
| --- | --- | --- |
| `docker compose up -d` | **round-robin** (padrão) | `tunnel-1.yaml` |
| `docker compose --profile lc up -d` | **least-connections** | `tunnel-1-lc.yaml` |

> **Nota:** Ao usar o profile `lc`, pare o tunnel padrão antes para evitar conflito de portas:
> ```bash
> docker compose down -v
> docker compose --profile lc up -d
> ```

## Máquinas e rede

| Container | Serviços | Acesso do host |
| --- | --- | --- |
| `tunnel-1` | tunnel `9090` (vPort), management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:9090`, `http://localhost:9190`, `http://localhost:9200` |
| `ishin-1` | proxy `19090`, management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:19090`, `http://localhost:19190`, `http://localhost:19200` |
| `ishin-2` | proxy `19090`, management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:29090`, `http://localhost:29190`, `http://localhost:29200` |
| `web-1` | nginx `80` | `http://localhost:18080` |
| `zipkin-1` | Zipkin `9411` | `http://localhost:39411` |

## Testes rápidos

Testar o nginx diretamente:

```bash
curl http://localhost:18080
```

Testar via tunnel (L4 LB → proxy → nginx):

```bash
curl http://localhost:9090
```

Testar o proxy diretamente (bypass tunnel):

```bash
curl http://localhost:19090
curl http://localhost:29090
```

## Observabilidade

### Dashboard

```bash
# Dashboard do ishin-1
curl http://localhost:19200/api/dashboard/health

# Dashboard do ishin-2
curl http://localhost:29200/api/dashboard/health
```

O Dashboard UI pode ser acessado em `http://localhost:19200` ou `http://localhost:29200`.

### Zipkin (Distributed Tracing)

```bash
# Health check
curl http://localhost:39411/health

# UI (abrir no browser)
# http://localhost:39411

# Traces recentes (após gerar tráfego)
curl "http://localhost:39411/api/v2/traces?limit=5"
```

## Admin API

A Admin API está habilitada em todos os nós com apiKey `nishisan`.

```bash
# Listar scripts
curl http://localhost:9190/admin/rules/list -H "X-API-Key: nishisan"

# Consultar versão
curl http://localhost:9190/admin/rules/version -H "X-API-Key: nishisan"
```

## Cluster

O cluster NGrid é formado por 3 nós:

- `tunnel-1` conhece `ishin-1:7100`, `ishin-2:7100`
- `ishin-1` conhece `tunnel-1:7100`, `ishin-2:7100`
- `ishin-2` conhece `tunnel-1:7100`, `ishin-1:7100`

Ver logs de um container:

```bash
docker compose logs -f tunnel-1
docker compose logs -f ishin-1
docker compose logs -f ishin-2
```

## Comandos úteis

Entrar em um container:

```bash
docker compose exec ishin-1 sh
docker compose exec web-1 sh
```

Reprovisionar (rebuild + restart):

```bash
docker compose down && docker compose up -d
```

Destruir o laboratório (com volumes):

```bash
docker compose down -v
```

## Diferenças em relação ao Vagrant

| Aspecto | Vagrant | Docker |
| --- | --- | --- |
| **RAM total** | ~10 GB | ~1.4 GB |
| **Zipkin storage** | Elasticsearch 8.x (persistente) | In-memory (efêmero) |
| **Startup** | ~5-10 min | ~30s |
| **Rede** | Private network 192.168.56.0/24 | Docker bridge (DNS interno) |
| **Instalação** | Pacote .deb + systemd | Imagem Docker pré-compilada |
| **SO** | Ubuntu 24.04 completo | Container baseado em JRE 21 |

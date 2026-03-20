# Docker Compose Test Case — Equivalente ao Vagrant Lab

Criar uma versão Docker Compose do ambiente de testes `ishin-gateway-test-case`, atualmente baseado em VMs Vagrant, usando a imagem Docker `lnishisan/ishin-gateway:latest`.

## Topologia Alvo

A topologia Docker replica fielmente o ambiente Vagrant:

| Container | Imagem | Papel | Portas Host |
|---|---|---|---|
| `tunnel-1` | `lnishisan/ishin-gateway:latest` | Tunnel L4 LB + Dashboard + Cluster | 9090, 9190, 9200 |
| `ishin-1` | `lnishisan/ishin-gateway:latest` | Proxy + Dashboard + Cluster | 19090, 19190, 19200 |
| `ishin-2` | `lnishisan/ishin-gateway:latest` | Proxy + Dashboard + Cluster | 29090, 29190, 29200 |
| `web-1` | `nginx:alpine` | Backend HTTP | 18080 |
| `zipkin-1` | `openzipkin/zipkin:3.5` | Distributed Tracing | 39411 |

> [!IMPORTANT]
> Diferenças em relação ao Vagrant:
> - **Zipkin simplificado**: sem Elasticsearch (o Zipkin in-memory é suficiente para lab/teste). No Vagrant usava ES 8.x com 3GB RAM — overkill para Docker.
> - **Recurso total**: ~1.5 GB RAM vs 10 GB do Vagrant.
> - **DNS interno**: Docker resolve hostnames via rede interna, sem precisar do `common.sh` com `/etc/hosts`.

## Proposed Changes

### Configurações dos Nós

Serão criados 3 adapter.yaml separados (um por nó ishin-gateway) dentro de `ishin-gateway-test-case/docker/configs/`.

#### [NEW] [tunnel-1.yaml](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker/configs/tunnel-1.yaml)

Configuração do tunnel L4 com cluster NGrid. Tradução direta do script `install_ishin_tunnel.sh`:

- `mode: tunnel`
- Cluster com seeds `tunnel-1:7100, ishin-1:7100, ishin-2:7100`
- Dashboard habilitado na porta 9200
- Admin API habilitada

#### [NEW] [ishin-1.yaml](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker/configs/ishin-1.yaml)

Configuração do proxy 1 com cluster. Tradução do `install_ishin.sh`:

- Listener HTTP na porta 19090 (virtualPort 9090)
- Backend apontando para `web-1:80`
- Cluster com seeds `tunnel-1:7100, ishin-2:7100`
- Dashboard com Zipkin query integrado
- Tunnel registration habilitado

#### [NEW] [ishin-2.yaml](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker/configs/ishin-2.yaml)

Idêntico ao ishin-1 mas com seeds `tunnel-1:7100, ishin-1:7100`.

#### [NEW] [default.conf](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker/configs/nginx/default.conf)

Config Nginx com health endpoint e página estática identificando o nó.

#### [NEW] [Rules.groovy](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker/configs/rules/default/Rules.groovy)

Rule pass-through (idêntica ao Vagrant).

---

### Docker Compose

#### [NEW] [docker-compose.yml](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker-compose.yml)

5 services:

1. **web-1**: `nginx:alpine`, volume-mount do `default.conf`, port `18080:80`, healthcheck
2. **zipkin-1**: `openzipkin/zipkin:3.5`, port `39411:9411`
3. **tunnel-1**: `lnishisan/ishin-gateway:latest`, config mount, env vars (`ISHIN_CLUSTER_NODE_ID=tunnel-1`), ports 9090/9190/9200, depends_on web-1 e zipkin-1
4. **ishin-1**: `lnishisan/ishin-gateway:latest`, config mount, env vars, ports 19090/19190/19200, depends_on tunnel-1
5. **ishin-2**: `lnishisan/ishin-gateway:latest`, config mount, env vars, ports 29090/29190/29200, depends_on tunnel-1

Todos com healthcheck via `wget -qO- http://127.0.0.1:<management_port>/actuator/health`.

Rede interna Docker padrão para resolução DNS entre containers.

---

### Scripts e Documentação

#### [NEW] [start.sh](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker/start.sh)

Script wrapper que:
- Faz `docker compose up -d`
- Aguarda health de cada service
- Exibe banner com endpoints (mesmo estilo do `start.sh` Vagrant)

#### [NEW] [README.md](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docker/README.md)

Documentação com:
- Requisitos (Docker + Docker Compose)
- Tabela de recursos (~1.5 GB RAM)
- Topologia e porta-mapping
- Comandos de uso rápido
- Testes de validação
- Diferenças em relação ao Vagrant

---

### Diagrama

#### [NEW] [docker_lab_topology.puml](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/docs/diagrams/docker_lab_topology.puml)

Diagrama PlantUML da topologia Docker, similar ao `lab_topology.puml` do Vagrant mas refletindo containers em vez de VMs.

## Verification Plan

### Automatizado

```bash
# 1. Subir o ambiente
cd ishin-gateway-test-case/docker
docker compose up -d

# 2. Aguardar startup (15-20s)
sleep 20

# 3. Testar backend direto
curl -sf http://localhost:18080 && echo "✅ web-1 OK"

# 4. Testar proxy direto (ishin-1)
curl -sf http://localhost:19090 && echo "✅ ishin-1 proxy OK"

# 5. Testar proxy direto (ishin-2)
curl -sf http://localhost:29090 && echo "✅ ishin-2 proxy OK"

# 6. Testar via tunnel
curl -sf http://localhost:9090 && echo "✅ tunnel-1 OK"

# 7. Testar management API
curl -sf http://localhost:9190/actuator/health && echo "✅ tunnel-1 mgmt OK"
curl -sf http://localhost:19190/actuator/health && echo "✅ ishin-1 mgmt OK"
curl -sf http://localhost:29190/actuator/health && echo "✅ ishin-2 mgmt OK"

# 8. Testar dashboards
curl -sf http://localhost:9200/api/dashboard/health && echo "✅ tunnel-1 dashboard OK"
curl -sf http://localhost:19200/api/dashboard/health && echo "✅ ishin-1 dashboard OK"
curl -sf http://localhost:29200/api/dashboard/health && echo "✅ ishin-2 dashboard OK"

# 9. Zipkin
curl -sf http://localhost:39411/health && echo "✅ zipkin OK"

# 10. Teardown
docker compose down
```

### Manual

O usuário pode verificar o dashboard via browser em `http://localhost:19200` e o Zipkin em `http://localhost:39411`.

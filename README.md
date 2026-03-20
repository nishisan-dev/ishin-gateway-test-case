# Laboratório Vagrant para ishin-gateway

Projeto para subir cinco VMs locais com Vagrant:

- `tunnel-1`: Ubuntu + `ishin-gateway latest` em **modo tunnel** (L4 TCP load balancer + Dashboard)
- `ishin-1`: Ubuntu + `ishin-gateway latest` em modo proxy + cluster (com Dashboard de Observabilidade)
- `ishin-2`: Ubuntu + `ishin-gateway latest` em modo proxy + cluster (com Dashboard de Observabilidade)
- `web-1`: Ubuntu + `nginx` (backend de teste)
- `zipkin-1`: Ubuntu + `Elasticsearch 8.x` + `Zipkin Server` (tracing com storage persistente)

O nó `tunnel-1` atua como ponto de entrada L4, recebendo conexões TCP e distribuindo entre os proxies registrados. Os dois nós proxy formam um cluster NGrid com `tunnel-1`, registram-se automaticamente no tunnel via `tunnel.registration`, e encaminham requests para `web-1`. Traces são exportados para `zipkin-1`.

## Requisitos

- Vagrant
- Um provider suportado pelo box escolhido:
  - `libvirt` com `vagrant-libvirt`
  - ou `VirtualBox`

### Recursos do host

| VM | vCPUs | RAM | Papel |
| --- | --- | --- | --- |
| `tunnel-1` | 2 | 2 GB | ishin-gateway tunnel L4 LB + dashboard + cluster |
| `ishin-1` | 2 | 2 GB | ishin-gateway proxy + dashboard + cluster |
| `ishin-2` | 2 | 2 GB | ishin-gateway proxy + dashboard + cluster |
| `web-1` | 2 | 1 GB | Nginx backend |
| `zipkin-1` | 2 | 3 GB | Elasticsearch + Zipkin Server |
| **Total** | **10** | **10 GB** | |

> O host precisa de no mínimo **12 GB de RAM livre** (10 GB para VMs + overhead do hypervisor) e **~20 GB de disco** para os box images e dados.

## Topologia

![Topologia do Lab](https://uml.nishisan.dev/proxy?src=https://raw.githubusercontent.com/nishisan-dev/ishin-gateway-test-case/main/docs/diagrams/lab_topology.puml)

## Subir o ambiente

A forma recomendada é usar o script `start.sh`, que sobe as VMs na ordem correta e exibe um resumo com todas as URLs ao final:

```bash
./start.sh
```

Para subir VMs específicas:

```bash
./start.sh web-1 zipkin-1
```

> O provider default é `libvirt`. Para usar VirtualBox, exporte: `VAGRANT_DEFAULT_PROVIDER=virtualbox`

### Subir manualmente (alternativa)

```bash
vagrant up web-1
vagrant up zipkin-1
vagrant up tunnel-1
vagrant up ishin-1
vagrant up ishin-2
```

## Máquinas e rede

| VM | IP privado | Serviços | Acesso do host |
| --- | --- | --- | --- |
| `tunnel-1` | `192.168.56.10` | tunnel `9090` (vPort), management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:9090`, `http://localhost:9190`, `http://localhost:9200` |
| `ishin-1` | `192.168.56.11` | proxy `19090`, management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:19090`, `http://localhost:19190`, `http://localhost:19200` |
| `ishin-2` | `192.168.56.12` | proxy `19090`, management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:29090`, `http://localhost:29190`, `http://localhost:29200` |
| `web-1` | `192.168.56.21` | nginx `80` | `http://localhost:18080` |
| `zipkin-1` | `192.168.56.31` | Zipkin `9411` | `http://localhost:39411` |

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

Se tudo estiver certo, todos os endpoints devem retornar a página HTML servida pelo `nginx`.

## Observabilidade

### Dashboard

O Dashboard de Observabilidade está habilitado por padrão em ambos os nós ishin-gateway:

```bash
# Dashboard do ishin-1
curl http://localhost:19200/api/dashboard/health

# Dashboard do ishin-2
curl http://localhost:29200/api/dashboard/health
```

O Dashboard UI pode ser acessado diretamente no browser em `http://localhost:19200` ou `http://localhost:29200`.

### Zipkin (Distributed Tracing)

O Zipkin Server roda na VM `zipkin-1` e coleta traces de ambos os nós ishin-gateway automaticamente:

```bash
# Health check do Zipkin
curl http://localhost:39411/health

# UI do Zipkin (abrir no browser)
# http://localhost:39411

# Consultar traces recentes (após gerar tráfego)
curl "http://localhost:39411/api/v2/traces?limit=5"
```

O Dashboard do ishin-gateway também faz proxy para o Zipkin, permitindo consultar traces diretamente pela UI:

```bash
curl http://localhost:19200/api/dashboard/traces
```

## Admin API e CLI

A Admin API está habilitada em ambos os nós com apiKey `nishisan`. O pacote `.deb` (latest) instala o utilitário `ishin-cli` em `/usr/bin/`.

### Usar o CLI para gerenciar rules

```bash
# Configurar a chave (uma vez, ou adicionar em /etc/ishin-gateway/cli.conf)
export ISHIN_API_KEY="nishisan"

# Listar scripts do bundle ativo
ishin-cli list

# Consultar versão ativa
ishin-cli version

# Deploy de rules a partir de um diretório
ishin-cli deploy /etc/ishin-gateway/rules
```

### Usar via curl (alternativa)

```bash
# Listar scripts
curl http://localhost:9190/admin/rules/list -H "X-API-Key: nishisan"

# Consultar versão
curl http://localhost:9190/admin/rules/version -H "X-API-Key: nishisan"

# Deploy
curl -X POST http://localhost:9190/admin/rules/deploy \
  -H "X-API-Key: nishisan" \
  -F "scripts=@/etc/ishin-gateway/rules/default/Rules.groovy"
```

### Deploy de rules em cluster

Ao fazer deploy via CLI ou Admin API em qualquer nó, o bundle é replicado automaticamente para todos os nós do cluster via NGrid DistributedMap. Os scripts são materializados em `/etc/ishin-gateway/rules` em todos os nós.

## Cluster

O cluster NGrid é formado por 3 nós com seeds cruzados:

- `tunnel-1` conhece `ishin-1:7100`, `ishin-2:7100`
- `ishin-1` conhece `tunnel-1:7100`, `ishin-2:7100`
- `ishin-2` conhece `tunnel-1:7100`, `ishin-1:7100`

Cada nó recebe um `nodeId` fixo via `ISHIN_CLUSTER_NODE_ID`.

Para verificar se os nós subiram, consulte os logs:

```bash
vagrant ssh tunnel-1 -c "sudo journalctl -u ishin-gateway -n 100 --no-pager"
vagrant ssh ishin-1 -c "sudo journalctl -u ishin-gateway -n 100 --no-pager"
vagrant ssh ishin-2 -c "sudo journalctl -u ishin-gateway -n 100 --no-pager"
vagrant ssh zipkin-1 -c "sudo journalctl -u zipkin -n 50 --no-pager"
```

Se o build expor actuator no management port, você também pode testar:

```bash
curl http://localhost:19190/actuator/health
curl http://localhost:29190/actuator/health
```

## Comandos úteis

Entrar em uma VM:

```bash
vagrant ssh ishin-1
vagrant ssh zipkin-1
```

Ver status dos serviços:

```bash
vagrant ssh ishin-1 -c "sudo systemctl status ishin-gateway --no-pager"
vagrant ssh zipkin-1 -c "sudo systemctl status zipkin --no-pager"
vagrant ssh web-1 -c "sudo systemctl status nginx --no-pager"
```

Reprovisionar:

```bash
vagrant provision
```

Destruir o laboratório:

```bash
vagrant destroy -f
```

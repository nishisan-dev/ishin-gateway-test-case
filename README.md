# Laboratório Vagrant para n-gate

Projeto para subir quatro VMs locais com Vagrant:

- `ngate-1`: Ubuntu + `n-gate v3.1.2` em cluster (com Dashboard de Observabilidade)
- `ngate-2`: Ubuntu + `n-gate v3.1.2` em cluster (com Dashboard de Observabilidade)
- `web-1`: Ubuntu + `nginx` (backend de teste)
- `zipkin-1`: Ubuntu + `Elasticsearch 8.x` + `Zipkin Server` (tracing com storage persistente)

Os dois nós `n-gate` formam um cluster NGrid com `replicationFactor: 2` e são configurados para encaminhar requests para a VM `web-1`. Traces são exportados automaticamente para `zipkin-1` e persistidos no Elasticsearch.

## Requisitos

- Vagrant
- Um provider suportado pelo box escolhido:
  - `libvirt` com `vagrant-libvirt`
  - ou `VirtualBox`

### Recursos do host

| VM | vCPUs | RAM | Papel |
| --- | --- | --- | --- |
| `ngate-1` | 2 | 2 GB | n-gate proxy + dashboard + cluster |
| `ngate-2` | 2 | 2 GB | n-gate proxy + dashboard + cluster |
| `web-1` | 2 | 1 GB | Nginx backend |
| `zipkin-1` | 2 | 3 GB | Elasticsearch + Zipkin Server |
| **Total** | **8** | **8 GB** | |

> O host precisa de no mínimo **10 GB de RAM livre** (8 GB para VMs + overhead do hypervisor) e **~15 GB de disco** para os box images e dados.

## Topologia

![Topologia do Lab](https://uml.nishisan.dev/proxy?src=https://raw.githubusercontent.com/nishisan-dev/n-gate-test-case/main/docs/diagrams/lab_topology.puml)

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
vagrant up ngate-1
vagrant up ngate-2
```

## Máquinas e rede

| VM | IP privado | Serviços | Acesso do host |
| --- | --- | --- | --- |
| `ngate-1` | `192.168.56.11` | proxy `9090`, management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:19090`, `http://localhost:19190`, `http://localhost:19200` |
| `ngate-2` | `192.168.56.12` | proxy `9090`, management `9190`, dashboard `9200`, cluster `7100` | `http://localhost:29090`, `http://localhost:29190`, `http://localhost:29200` |
| `web-1` | `192.168.56.21` | nginx `80` | `http://localhost:18080` |
| `zipkin-1` | `192.168.56.31` | Zipkin `9411` | `http://localhost:39411` |

## Testes rápidos

Testar o nginx diretamente:

```bash
curl http://localhost:18080
```

Testar o proxy no primeiro n-gate:

```bash
curl http://localhost:19090
```

Testar o proxy no segundo n-gate:

```bash
curl http://localhost:29090
```

Se tudo estiver certo, os dois endpoints do `n-gate` devem retornar a página HTML servida pelo `nginx`.

## Observabilidade

### Dashboard

O Dashboard de Observabilidade está habilitado por padrão em ambos os nós n-gate:

```bash
# Dashboard do ngate-1
curl http://localhost:19200/api/dashboard/health

# Dashboard do ngate-2
curl http://localhost:29200/api/dashboard/health
```

O Dashboard UI pode ser acessado diretamente no browser em `http://localhost:19200` ou `http://localhost:29200`.

### Zipkin (Distributed Tracing)

O Zipkin Server roda na VM `zipkin-1` e coleta traces de ambos os nós n-gate automaticamente:

```bash
# Health check do Zipkin
curl http://localhost:39411/health

# UI do Zipkin (abrir no browser)
# http://localhost:39411

# Consultar traces recentes (após gerar tráfego)
curl "http://localhost:39411/api/v2/traces?limit=5"
```

O Dashboard do n-gate também faz proxy para o Zipkin, permitindo consultar traces diretamente pela UI:

```bash
curl http://localhost:19200/api/dashboard/traces
```

## Admin API e CLI

A Admin API está habilitada em ambos os nós com apiKey `nishisan`. O pacote `.deb` v3.1.2 instala o utilitário `ngate-cli` em `/usr/bin/`.

### Usar o CLI para gerenciar rules

```bash
# Configurar a chave (uma vez, ou adicionar em /etc/n-gate/cli.conf)
export NGATE_API_KEY="nishisan"

# Listar scripts do bundle ativo
ngate-cli list

# Consultar versão ativa
ngate-cli version

# Deploy de rules a partir de um diretório
ngate-cli deploy /etc/n-gate/rules
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
  -F "scripts=@/etc/n-gate/rules/default/Rules.groovy"
```

### Deploy de rules em cluster

Ao fazer deploy via CLI ou Admin API em qualquer nó, o bundle é replicado automaticamente para todos os nós do cluster via NGrid DistributedMap. Os scripts são materializados em `/etc/n-gate/rules` em todos os nós.

## Cluster

O cluster é configurado automaticamente com estes seeds:

- `ngate-1` conhece `ngate-2:7100`
- `ngate-2` conhece `ngate-1:7100`

Cada nó recebe um `nodeId` fixo via `NGATE_CLUSTER_NODE_ID`.

Para verificar se os nós subiram, consulte os logs:

```bash
vagrant ssh ngate-1 -c "sudo journalctl -u n-gate -n 100 --no-pager"
vagrant ssh ngate-2 -c "sudo journalctl -u n-gate -n 100 --no-pager"
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
vagrant ssh ngate-1
vagrant ssh zipkin-1
```

Ver status dos serviços:

```bash
vagrant ssh ngate-1 -c "sudo systemctl status n-gate --no-pager"
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

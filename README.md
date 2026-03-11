# Laboratorio Vagrant para n-gate

Projeto para subir tres VMs locais com Vagrant:

- `ngate-1`: Ubuntu + `n-gate v2.1.0` em cluster
- `ngate-2`: Ubuntu + `n-gate v2.1.0` em cluster
- `web-1`: Ubuntu + `nginx`

Os dois nós `n-gate` formam um cluster NGrid com `replicationFactor: 2` e sao configurados para encaminhar requests para a VM `web-1`.

## Requisitos

- Vagrant
- Um provider suportado pelo box escolhido:
- `libvirt` com `vagrant-libvirt`
- ou `VirtualBox`

## Subir o ambiente

```bash
vagrant up web-1
vagrant up ngate-1
vagrant up ngate-2
```

Com `libvirt`:

```bash
vagrant up web-1 --provider=libvirt
vagrant up ngate-1 --provider=libvirt
vagrant up ngate-2 --provider=libvirt
```

Subir em sequencia reduz problemas de bootstrap do cluster.

## Maquinas e rede

| VM | IP privado | Servico principal | Acesso do host |
| --- | --- | --- | --- |
| `ngate-1` | `192.168.56.11` | `n-gate` em `9090`, management em `9190`, cluster em `7100` | `http://localhost:19090`, `http://localhost:19190` |
| `ngate-2` | `192.168.56.12` | `n-gate` em `9090`, management em `9190`, cluster em `7100` | `http://localhost:29090`, `http://localhost:29190` |
| `web-1` | `192.168.56.21` | `nginx` em `80` | `http://localhost:18080` |

## Testes rapidos

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

Se tudo estiver certo, os dois endpoints do `n-gate` devem retornar a pagina HTML servida pelo `nginx`.

## Cluster

O cluster e configurado automaticamente com estes seeds:

- `ngate-1` conhece `ngate-2:7100`
- `ngate-2` conhece `ngate-1:7100`

Cada no recebe um `nodeId` fixo via `NGATE_CLUSTER_NODE_ID`.

Para verificar se os nos subiram, consulte os logs:

```bash
vagrant ssh ngate-1 -c "sudo journalctl -u n-gate -n 100 --no-pager"
vagrant ssh ngate-2 -c "sudo journalctl -u n-gate -n 100 --no-pager"
```

Se o build expor actuator no management port, voce tambem pode testar:

```bash
curl http://localhost:19190/actuator/health
curl http://localhost:29190/actuator/health
```

## Comandos uteis

Entrar em uma VM:

```bash
vagrant ssh ngate-1
```

Ver status dos serviços:

```bash
vagrant ssh ngate-1 -c "sudo systemctl status n-gate --no-pager"
vagrant ssh web-1 -c "sudo systemctl status nginx --no-pager"
```

Reprovisionar:

```bash
vagrant provision
```

Destruir o laboratorio:

```bash
vagrant destroy -f
```

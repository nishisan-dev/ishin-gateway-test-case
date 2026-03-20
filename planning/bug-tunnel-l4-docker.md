# Bug: Tunnel L4 não abre listener TCP na porta 9090 (Docker Compose)

## Status: CORRIGIDO

> **Solução aplicada:** Substituído pré-seed estático por autodiscovery dinâmico — `TunnelRegistry` agora deriva registry keys dos peers do cluster NGrid a cada ciclo de polling via `ClusterService.getClusterPeerNodeIds()`.

## Contexto

O ambiente Docker Compose do `ishin-gateway-test-case/docker/` foi criado para replicar a topologia Vagrant. **11/12 testes passaram** — tudo funciona exceto o tunnel L4 na porta 9090.

O tunnel L4 é dinâmico: quando proxies se registram via `DistributedMap` NGrid com um `TunnelRegistryEntry` contendo `ListenerRegistration(virtualPort=9090, realPort=19090)`, o `TunnelRegistry` detecta e chama `TunnelEngine.openListener(9090)` que faz bind TCP.

## Sintoma

- `tunnel-1` inicia corretamente (TunnelEngine, TunnelRegistry, Dashboard, Cluster com 3 membros)
- Os proxies `ishin-1`/`ishin-2` publicam com sucesso:
  ```
  Published tunnel registry entry: tunnel:registry:ishin-1 → TunnelRegistryEntry{nodeId='ishin-1', host='172.21.0.5', status='ACTIVE', listeners=1, weight=100}
  ```
- O tunnel-1 **NÃO logou** `Pre-seeded registry key` — a lógica de pré-seed em `TunnelService.java:126-142` não executou
- Nenhum `VirtualPortGroup created` ou `Listener opened` nos logs
- Sem porta 9090 em LISTEN no container (confirmado via `/proc/net/tcp`)

## Causa raiz provável

Arquivo: `src/main/java/dev/nishisan/ishin/gateway/tunnel/TunnelService.java` linhas 126-142:

```java
// Pré-popular knownRegistryKeys a partir dos seeds do cluster.
if (config.getCluster() != null && config.getCluster().getSeeds() != null) {
    String localNodeId = clusterService.getLocalNodeId();
    for (String seed : config.getCluster().getSeeds()) {
        String[] parts = seed.split(":");
        String seedNodeId = parts[0];
        if (!seedNodeId.equals(localNodeId)) {
            String registryKey = TunnelRegistry.REGISTRY_KEY_PREFIX + seedNodeId;
            tunnelRegistry.addKnownRegistryKey(registryKey);
            logger.info("Pre-seeded registry key for polling: {}", registryKey);
        }
    }
}
```

O branch `config.getCluster() != null && config.getCluster().getSeeds() != null` **não entrou** — possibilidades:

1. `configurationManager.loadConfiguration()` retorna um `ServerConfiguration` onde o `ClusterConfiguration.seeds` é `null` quando carregado no contexto do `TunnelService` (@Order(30))
2. O `ClusterService` (@Order(20)) inicia o cluster corretamente, mas ele carrega a config separadamente e o YAML pode ser parseado de forma diferente
3. **Timing**: no Docker, os 3 nós sobem quase simultaneamente (~1s). No Vagrant, há delays de minutos entre VMs

## Fluxo de referência (como funciona no Vagrant)

```
ClusterService (@Order 20)  → inicia NGrid, usa seeds para descobrir peers
TunnelService  (@Order 30)  → obtém DistributedMap, cria TunnelRegistry/TunnelEngine
                             → pré-popula knownRegistryKeys dos seeds
                             → TunnelRegistry.start() → poller thread busca keys no DistributedMap
                             → quando encontra TunnelRegistryEntry com listeners
                             → cria VirtualPortGroup → chama onGroupCreated
                             → TunnelEngine.openListener(9090)
```

## Arquivos relevantes

- `src/main/java/dev/nishisan/ishin/gateway/tunnel/TunnelService.java` — orquestrador, pré-seed das keys
- `src/main/java/dev/nishisan/ishin/gateway/tunnel/TunnelRegistry.java` — poller do DistributedMap
- `src/main/java/dev/nishisan/ishin/gateway/tunnel/TunnelEngine.java` — abre listeners TCP
- `src/main/java/dev/nishisan/ishin/gateway/tunnel/TunnelRegistrationService.java` — proxy side, publica entries
- `src/main/java/dev/nishisan/ishin/gateway/manager/ConfigurationManager.java` — carrega adapter.yaml

## Investigação sugerida

1. Adicionar log de debug em `TunnelService.onStartup()` **antes** do `if` para verificar o valor de `config.getCluster()` e `config.getCluster().getSeeds()`
2. Verificar se `ConfigurationManager.loadConfiguration()` retorna seeds corretamente quando chamado pelo `TunnelService`
3. Testar se o issue é reprodutível no Vagrant ou apenas no Docker (timing)

## Ambiente para reprodução

```bash
cd ishin-gateway-test-case/docker/
docker compose up -d
# Aguardar 40s
docker compose logs tunnel-1 | grep -i "pre-seeded"  # deve estar vazio = bug
docker compose logs ishin-1 | grep "Published tunnel"  # deve ter entry = proxy OK
docker compose down -v
```

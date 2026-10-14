# AgroField × Zabbix 8.0 APM — Roteiro de Execução

> Laboratório de estudo: usar o AgroField (app real, não "hello world") para aprender APM/OpenTelemetry no Zabbix 8.0, gerando conteúdo técnico original em PT-BR a cada fase.

---

## Fase 0 — Preparar o laboratório Zabbix 8.0 ✅ CONCLUÍDA (08/10/2026)
Objetivo: ter o Zabbix 8.0 rodando e pronto para receber dados, antes de tocar no AgroField.

- [x] Subir stack do Zabbix 8.0 via Docker Compose neste diretório (`zabbix8/`): `postgres-zabbix`, `clickhouse`, `zabbix-server`, `zabbix-web`, `zabbix-proxy`.
- [x] Validar frontend web do Zabbix acessível (`http://localhost:8080`, Admin/zabbix) e host "Zabbix server" ativo.
- [x] Confirmado: quem recebe OTLP/gRPC é o **Zabbix Proxy** (não o server), e precisa de **ClickHouse** como datastore de telemetria.
- [x] AgroField clonado em `/home/ubuntu/laboratorio/agrofield` (https://github.com/HeitorCBraga/agrofield), como sibling de `zabbix8/`.
- [x] Rede Docker externa `agrofield-observability` criada e compartilhada pelos dois `docker-compose.yml` (serviço `backend` do AgroField e `zabbix-server`/`zabbix-proxy` do Zabbix).

### Achados técnicos importantes (para a Fase 1 usar)
- **Zabbix 8.0 ainda não é GA** — estamos em rc2 (imagem `trunk-alpine`, sem tag `8.0` fixa ainda no Docker Hub). Risco de bleeding edge assumido.
- **Formato correto do `ZBX_TELEMETRYPROVIDER_0`** (server e proxy): `{"provider":"clickhouse","url":"http://clickhouse:8123","db":"<nome>","username":"...","password":"..."}`. Campos errados usados inicialmente (`type`/`host`/`port`/`database`) geram erro `provider must be clickhouse`.
- **As env vars documentadas do coletor APM não funcionam ainda no entrypoint trunk**: `ZBX_STARTAPMCOLLECTORS`, `ZBX_APMLISTENIP`, `ZBX_APMLISTENPORT` são silenciosamente ignoradas (feature nova, entrypoint Go ainda não as mapeia). Contornado com um **hook de entrypoint** (`proxy-entrypoint.d/10-apm.sh`, montado em `/etc/zabbix/entrypoint.d/` no container), que roda depois da geração da config e antes do `zabbix_proxy` iniciar, e injeta direto no `zabbix_proxy.conf`: `StartAPMCollectors=1`, `APMListenIP=0.0.0.0`, `APMListenPort=4317`.
- Isso exigiu rodar o container `zabbix-proxy` como root (`user: "0:0"`), porque `/etc/zabbix/zabbix_proxy.conf` é root-owned e o hook precisa escrever nele.
- Proxy precisa ser **registrado manualmente** no Zabbix (via API `proxy.create`, modo ativo/`operating_mode:0`) com o mesmo nome do `ZBX_HOSTNAME` do container (`zabbix-proxy`) — senão server e proxy ficam em loop de erro `"proxy not found"`.
- **Resultado final confirmado**: coletor OTLP/gRPC do proxy escutando em `0.0.0.0:4317`, acessível em `localhost:4317` do host e em `zabbix-proxy:4317` dentro da rede `agrofield-observability` — pronto para o backend do AgroField apontar o exportador OTel pra lá na Fase 1.

---

## Fase 1 — Instrumentar o backend com OpenTelemetry
Objetivo: traces reais de uma API Node.js chegando no Zabbix 8.0.
Gancho de conteúdo: "Zabbix 8.0 recebendo traces reais via OpenTelemetry de uma API Node.js" (ineditismo PT-BR).

- [ ] Adicionar dependências OTel no backend Fastify: `@opentelemetry/sdk-node`, `@opentelemetry/auto-instrumentations-node`, exportador OTLP (`@opentelemetry/exporter-trace-otlp-http` ou grpc).
- [ ] Criar arquivo de bootstrap de instrumentação (ex: `instrumentation.ts`), carregado antes do app (`--require` ou `node --import`).
- [ ] Instrumentar automaticamente: requisições HTTP do Fastify + queries do Prisma (verificar se precisa de instrumentação manual para Prisma, já que o auto-instrument nem sempre cobre).
- [ ] Configurar exportador para apontar para o endpoint OTLP do Zabbix Proxy/Collector definido na Fase 0.
- [ ] Gerar tráfego real (login, CRUD de Fazenda/Área/Plantio) e confirmar que os traces aparecem no Zabbix 8.0.
- [ ] Validar atributos relevantes no trace (rota, status HTTP, duração, query SQL) — necessários para a correlação da Fase 2.
- [ ] Escrever o artigo/post da Fase 1 com prints reais do Zabbix mostrando os traces.

---

## Fase 2 — CEP correlacionando erro + métrica (módulo de clima)
Objetivo: usar correlação de eventos (CEP) do Zabbix 8.0 para unir falha de API externa + degradação de performance num único Problem.
Gancho: "Usando CEP do Zabbix 8.0 para correlacionar falha de API externa com degradação de performance".

- [ ] Implementar módulo mínimo de clima/solo no backend consumindo API externa (INMET ou OpenWeather).
- [ ] Garantir que chamadas a essa API fiquem instrumentadas (span próprio, com atributos de latência e status).
- [ ] Criar triggers no Zabbix: (a) taxa de erro 5xx na rota do clima, (b) latência alta no trace dessa rota.
- [ ] Configurar regra de correlação de eventos (CEP) no Zabbix 8.0 unindo os dois triggers num Problem só.
- [ ] Provocar falhas de propósito: timeout (mock/delay), rate limit (bater o limite da API real ou simular 429), API fora do ar (desligar/bloquear endpoint).
- [ ] Capturar no Zabbix o Problem correlacionado disparando corretamente nos 3 cenários.
- [ ] Escrever o artigo da Fase 2 com a configuração da regra CEP e evidência dos 3 cenários de falha.

---

## Fase 3 — Monitoramento nativo de uso de IA
Objetivo: testar o monitoramento nativo de consumo de IA do Zabbix 8.0 e comparar com a integração custom Groq/Llama do projeto Vale.
Gancho: ângulo de autoridade por já ter comparação real anterior.

- [ ] Adicionar feature mínima com LLM no AgroField (ex: geração de descrição de produto/plantio).
- [ ] Identificar que provedor de LLM o Zabbix 8.0 monitora nativamente (OpenAI, Anthropic, etc.) e usar um compatível.
- [ ] Configurar o monitoramento nativo de IA do Zabbix 8.0 apontando para essa feature.
- [ ] Levantar as métricas nativas disponíveis (tokens, custo, latência, taxa de erro) e comparar com o que foi feito manualmente no projeto Vale (Groq/Llama).
- [ ] Escrever o artigo da Fase 3 com a comparação lado a lado (nativo Zabbix vs. integração custom).

---

## Fase 4 — Comparação final: Zabbix 8.0 OTel nativo vs. Datadog APM
Objetivo: fechar a série com um comparativo direto, já que os dois estão sendo estudados no mesmo projeto.

- [ ] Levantar critérios de comparação (setup, custo, cobertura de instrumentação automática, qualidade da correlação/CEP vs. Datadog Watchdog, UX do APM, suporte a IA).
- [ ] Rodar o mesmo cenário de falha (módulo de clima) nos dois sistemas, se ainda não tiver sido feito em paralelo.
- [ ] Escrever o artigo final consolidando as 4 fases com tabela comparativa.

---

## Pendências abertas
- ~~Confirmar o path local do AgroField~~ — resolvido: clonado de https://github.com/HeitorCBraga/agrofield para `/home/ubuntu/laboratorio/agrofield` (sibling de `zabbix8/`).
- ~~Confirmar papel do diretório `zabbix8/`~~ — resolvido: só infra do Zabbix 8.0; o app fica em `agrofield/`.

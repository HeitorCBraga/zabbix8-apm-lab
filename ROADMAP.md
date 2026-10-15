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
- ~~**Resultado final confirmado**: coletor OTLP/gRPC escutando em `0.0.0.0:4317`~~ — **CORREÇÃO (descoberta na Fase 1):** essa validação foi um **falso positivo**. O teste feito a partir do host (`echo > /dev/tcp/127.0.0.1/4317`) passou porque quem aceita a conexão no host é o `docker-proxy`, não o container. Na prática o listener **não estava aberto**: o log dizia `[apm worker #1] thread started`, mas a porta recusava conexão a partir de outro container. O listener só abriu depois das configurações via UI descritas nos "Achados da Fase 1". Moral: valide a porta de **dentro da rede Docker**, a partir de quem vai usá-la (`docker compose exec backend nc -zv zabbix-proxy 4317`).

---

## Fase 1 — Instrumentar o backend com OpenTelemetry ✅ PIPELINE FUNCIONANDO (15/10/2026)
Objetivo: traces reais de uma API Node.js chegando no Zabbix 8.0.
Gancho de conteúdo: "Zabbix 8.0 recebendo traces reais via OpenTelemetry de uma API Node.js" (ineditismo PT-BR).

```
backend (OTel SDK) ──OTLP/gRPC──> zabbix-proxy:4317 ──grava──> ClickHouse (otel_traces) <──lê── Zabbix web (APM → Traces)
```

- [x] Adicionar dependências OTel no backend Fastify: `sdk-node`, `auto-instrumentations-node`, `exporter-trace-otlp-grpc`, `resources`, `semantic-conventions`.
- [x] Criar bootstrap de instrumentação (`backend/src/instrumentation.ts`), carregado antes do app com `node --import ./dist/instrumentation.js` (Dockerfile) e `tsx watch --import ./src/instrumentation.ts` (script `dev`). Endpoint via `OTEL_EXPORTER_OTLP_ENDPOINT=http://zabbix-proxy:4317` no `docker-compose.yml` do AgroField.
- [x] Configurar exportador para o Zabbix Proxy (rede Docker `agrofield-observability`).
- [x] Gerar tráfego (`POST /auth/login`) e confirmar os traces em **APM → Traces** (5 requisições = 5 spans, serviço `agrofield-backend`).
- [ ] Instrumentar a **rota** do Fastify e as **queries do Prisma** (ver "Limitações atuais").
- [ ] Validar atributos relevantes no trace (rota, status HTTP, duração, query SQL) — necessários para a correlação da Fase 2. Hoje temos método, `url.path`, status HTTP e duração; falta nome da rota e SQL.
- [ ] Escrever o artigo/post da Fase 1 com prints reais do Zabbix mostrando os traces.

### Achados da Fase 1 (o que a documentação não diz)

**O APM exige configuração em 3 lugares, não só no arquivo de conf:**
1. **Arquivo de conf do proxy** (via hook de entrypoint da Fase 0): `StartAPMCollectors`, `APMListenIP`, `APMListenPort` — cria o coletor e abre a porta.
2. **UI → Administration → Data source → APM**: URL `http://clickhouse:8123`, banco `zabbix_telemetry`, autenticação por usuário/senha. É uma configuração **global**, guardada no banco do Zabbix (`settings.apm_global_db`) — não é env var nem arquivo.
3. **UI → Administration → Proxies → `zabbix-proxy` → aba APM → "Data collection enabled"** (vem **desabilitado** por padrão).

Antes desses dois passos de UI, o log do proxy dizia `apm worker #1 thread started`, mas o listener não abria (`connection refused`). Depois deles, o log passou a mostrar `[apm manager #1] Open Telemetry collector listening on 0.0.0.0:4317`. Fizemos os dois passos juntos, então **não sabemos qual dos dois, sozinho, abre a porta**.

**O proxy grava direto no ClickHouse** (o binário tem `apm_clickhouse_write_value`; não é o server que grava). Prova: com o ClickHouse vazio, o log do proxy mostrou `Table zabbix_telemetry.otel_traces does not exist (UNKNOWN_TABLE)`.

**As tabelas `otel_*` não são criadas pelo Zabbix na rc2 — é preciso criá-las à mão.** Conferido em: página *Data source* da documentação 8.0 (só lista os campos e o botão Test, que apenas executa `SELECT 1`), página *APM*, página *ClickHouse setup* (só trata das tabelas `history_*`), a pasta oficial `database/clickhouse` no git do Zabbix (só scripts `history_*`) e o interior das imagens do proxy, server e web (nenhum `CREATE TABLE` de `otel_*`). O proxy conhece sete tabelas pelo nome: `otel_traces`, `otel_logs`, `otel_metrics_gauge`, `otel_metrics_sum`, `otel_metrics_histogram`, `otel_metrics_exponential_histogram`, `otel_metrics_summary`.
- Criamos só `otel_traces` (nosso SDK só envia traces): `clickhouse-init/otel_traces.sql`. Aplicar com:
  `docker exec -i zabbix8-clickhouse-1 clickhouse-client --user zabbix --password zabbix --multiquery < clickhouse-init/otel_traces.sql`
- O DDL é adaptado do repositório da comunidade [lucasmokan/zabbix-8rc1-apm-docker](https://github.com/lucasmokan/zabbix-8rc1-apm-docker) (feito para a rc1). Diferença importante em relação ao schema padrão do exporter OTel: o proxy insere **por posição de coluna** e envia timestamps como decimal, então as colunas são `TimestampRaw Decimal(19,9)` e `Timestamp` é `MATERIALIZED`. **Não reordene as colunas.**
- Pendente: `otel_logs` e `otel_metrics_*` (SQLs no mesmo repo da comunidade) quando passarmos a enviar logs/métricas.
- Pendente: montar `clickhouse-init/` como `/docker-entrypoint-initdb.d` no container do ClickHouse para criar as tabelas sozinho na primeira subida.

**O `ZBX_TELEMETRYPROVIDER_0` parece não ser o que grava os traces.** A documentação o associa aos itens do tipo *telemetry query*. Não testamos removê-lo; ele continua no compose.

### Outros problemas encontrados no caminho
- **`ZBX_DEBUGLEVEL=4` derrubou o proxy**: log em excesso atrapalhou a sincronização entre os processos (`failed to wait for the runlevel 1`) e o container entrou em loop de restart (8 reinícios em ~40 s). Revertido; não usar nível 4 neste lab.
- **Disco de 14 GB lotou (96%)** durante o `docker compose build` (`no space left on device` ao exportar a imagem). Liberado com `docker builder prune -af` e removendo versões antigas de `~/.vscode-server/cli/servers/` (~2,6 GB; manter só a versão em uso).
- **Node 18 no host vs. Node 22 no container**: os avisos `EBADENGINE` no `npm install` do host são irrelevantes, o app roda no Node 22 da imagem.
- **Banco do AgroField vazio** (`public.users does not exist`): o volume do Postgres era novo. A imagem de runtime não contém a pasta `prisma/`, então `prisma migrate deploy` dentro do container falha; rodamos do host: `DATABASE_URL=postgresql://agrofield:agrofield@localhost:5432/agrofield npx prisma migrate deploy`.
- **Faixa de IP**: o bridge Docker `agrofield-observability` usa `172.18.0.0/16`. Não conflita com a rede do host (`10.72.0.0/22`), mas conflitaria com uma VPN que roteie `172.18.0.0/16`.
- **Tag `trunk-alpine` é móvel**: as imagens podem mudar sem aviso. Pendente fixar uma tag/digest.

### Limitações atuais dos traces
- Só há **1 span por trace**, gerado por `@opentelemetry/instrumentation-http`. O nome do span é apenas o método (`POST`); a rota aparece só como atributo `url.path`.
- **Não há** instrumentação do Fastify instalada (nem `instrumentation-fastify` nem `@fastify/otel`), e o **Prisma não é coberto** pelo auto-instrument.
- No vídeo/demo de referência da comunidade, os traces têm árvores de 7 a 14 spans com nomes como `POST /api/store/checkout` — isso vem de instrumentação do framework + **spans manuais** + vários serviços propagando contexto, não de configuração do Zabbix.
- `StatusCode` fica `Unset` em respostas 4xx (ex.: login inválido, 401); o OTel só marca erro em 5xx para spans de servidor.

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

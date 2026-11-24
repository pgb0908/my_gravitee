# 나만의 LLM Gateway 계획

## 최종 목표

Gravitee Gateway의 핵심만 가져와 **새 Gateway를 만듭니다.** 지금처럼 플러그인으로 기능을 확장할 수 있게 하면서, Gravitee의 단점은 보완합니다. 첫 활용처는 **LLM Gateway**입니다.

이 문서에서 말하는 Gravitee의 단점은 다음과 같습니다.

| 단점 | 이 계획에서 대응하는 곳 |
|---|---|
| 핵심 코드가 저장소 수십 개로 흩어져 있고, 최근 버전은 비공개 피드에만 배포됨. 공개 소스만으로 빌드하려면 21개 저장소를 직접 빌드해야 함 | Phase 5: 필요한 라이브러리를 새 저장소로 흡수 |
| 기동에 필요한 부품이 외부 플러그인 zip으로 나뉘어 있음 (zip이 하나 빠지면 기동 실패. 예: `NoClusterManagerException`) | Phase 5: 단일 노드 구현 내장 |
| Gateway 곳곳에 엔터프라이즈 라이선스 검사가 얽혀 있음 | Phase 5: license 제거 |
| V2(legacy)와 V4 실행 엔진이 함께 있어서 코드가 큼 | Phase 3: V2 제거 |
| API 정의를 DB 배포 이벤트 형식으로만 읽음 (파일로 쓰려면 이중으로 감싸야 함) | Phase 3: 파일 기반 로더 |

- 작성일: 2026-11-24 (같은 날 최종 목표 기준으로 재구성)
- 기준 브랜치: `chore/gateway-only` (upstream `2b0ebc04e76` 기반)

## 로드맵

진행은 두 단계로 나뉩니다. **1단계는 이 저장소에서** 코드를 이해하고 LLM 플러그인을 만듭니다. **2단계는 새 저장소에서** Gateway를 재구성합니다.

```
1단계: 이 저장소 (upstream 구조 유지)          2단계: 새 저장소 (upstream 추적 중단)
┌────────────────────────────────────┐        ┌─────────────────────────────────────────┐
│ Phase 1  요청 경로 이해 (디버거)      │        │ Phase 5  gravitee-node 흡수와 축소       │
│ Phase 2  llm-openai 플러그인 MVP     │ ─────▶ │          (외부 라이브러리 흡수의 첫 대상)  │
│ Phase 3  덜 중요한 기능 걷어내기      │        │ 이후     플러그인 API 독립, Spring 결정   │
└────────────────────────────────────┘        └─────────────────────────────────────────┘
               Phase 4  LLM 기능 확장 (백로그. 두 단계와 병행할 수 있음)
```

| Phase | 어디서 | 목적 | 상태 |
|---|---|---|---|
| 1 | 이 저장소 | V4 요청 경로와 endpoint connector 계약 이해 | 진행 중 |
| 2 | 이 저장소 | `llm-openai` endpoint 플러그인 MVP. 이후 단계의 **회귀 테스트 안전망**도 함께 만듦 | 대기 |
| 3 | 이 저장소 | 쓰지 않는 기능을 걷어내 재구성할 범위를 줄임 | 대기 |
| 4 | 어디서든 | LLM 기능 확장 (스트리밍, 라우팅 등) | 백로그 |
| 5 | 새 저장소 | gravitee-node를 내부 모듈로 흡수하고 축소 | 대기 (Phase 2 이후) |

## 확정한 결정

### 1단계 (이 저장소)

| 항목 | 결정 |
|---|---|
| MVP 기능 | OpenAI 호환 요청 중계 + **(a) provider 인증 주입**, **(b) OpenAI API 경로 고정**, **(d) 사용량(usage) 기록** |
| 연결 대상 | OpenAI 호환 API. 개발과 확인은 **로컬 Ollama**(`/v1`)로 함 |
| 재구성 수준 | **구조 유지, 기능만 걷어내기.** 패키지명과 모듈 구조를 유지해 그동안은 upstream 수정을 받을 수 있게 함 |
| 설정 관리 | **파일만** 사용 (`gravitee.yml`, `apis/*.json`). DB와 Management API 없음 |
| Phase 1 진행 | 직접 디버거로 따라가고, 막히는 부분은 질문 |

### 2단계 (새 Gateway)

| 항목 | 결정 |
|---|---|
| upstream | **재구성 시점부터 추적을 끊음.** 새 저장소로 독립하고, 필요한 upstream 수정만 직접 가져옴 |
| 플러그인 호환 | **초기에는 기존 Gravitee 플러그인 zip과 바이너리 호환을 유지하고, 자체 플러그인 API가 안정되면 끊음.** 호환 기간에는 `io.gravitee.node.api.*`, `gravitee-gateway-api` 같은 API의 패키지명과 시그니처를 바꾸지 않음 |
| 배포 형태 | **단일 노드 우선.** 수평 확장은 상태 없는 인스턴스 여러 개와 로드밸런서로 함. 노드 간 공유 상태가 필요해지면 Redis 같은 외부 저장소로 해결 |
| Spring | **나중에 결정.** 그때까지는 유지하되, 결정할 때 영향 범위가 좁도록 경계를 정리해 둠 |

## 배경 사실

- OpenAI 호환 "중계"만 할 거라면 기존 `http-proxy` endpoint로도 됩니다. 그래서 직접 만드는 플러그인은 단순 프록시가 못 하는 (a), (b), (d)를 맡습니다.
- Gravitee에는 `ApiType.LLM_PROXY`가 정의되어 있지만, 이를 처리하는 플러그인(`gravitee-entrypoint-llm-proxy` 등)은 공개 저장소에 없어서 엔터프라이즈 전용으로 보입니다. 직접 만들어야 하고, 참고할 공개 구현이 없습니다.
- Gateway는 entrypoint, endpoint, policy, reactor를 모두 **플러그인 zip**으로 읽습니다. 공개 예제로 `endpoint-http-proxy`(main 코드 약 2,000줄)가 이 저장소에 있습니다.
- 모듈별 역할과 빌드에 필요한 모듈은 저장소 루트의 `MODULES.md`에 정리되어 있습니다.
- Gateway의 뼈대(객체 연결, 설정 주입, 기동 순서, 플러그인별 자식 컨텍스트)는 **Spring + gravitee-node**가 맡습니다. **Vert.x**는 네트워크 입출력을, **RxJava**는 요청 처리 파이프라인을 맡습니다. 요청을 처리하는 동안에는 Spring이 관여하지 않습니다.

## 구현 방식: endpoint connector 플러그인

```
client ──▶ [entrypoint: http-proxy] ──▶ plan / flow / policies ──▶ [endpoint: llm-openai] ──▶ Ollama (/v1)
              기존 그대로                   기존 그대로                  새로 만들 플러그인
```

- API는 기존 **V4 PROXY 타입**으로 정의하고, endpoint 타입만 새 플러그인(가칭 `llm-openai`)으로 지정합니다.
- entrypoint, 플랜(Keyless/API Key), flow와 정책, local sync는 그대로 씁니다. 새로 만드는 범위가 가장 작습니다.
- 다른 선택지는 지금 하지 않습니다.
  - **reactor 플러그인**(`LLM_PROXY` 타입 전용 실행기): 자유도는 가장 높지만 요청 파이프라인 전체를 다시 만들어야 합니다. 필요가 생기면 다시 검토합니다.
  - **policy만으로 구현**: provider 연결과 인증은 endpoint가 맡는 게 구조에 맞습니다.
- 이 플러그인은 2단계에서도 그대로 씁니다. 플러그인 호환을 유지하는 동안에는 새 Gateway에도 같은 zip을 꽂을 수 있습니다.

---

# 1단계: 이 저장소에서

## Phase 1: 코드 이해 (직접 디버거로 따라가기)

목표는 **V4 HTTP 요청 한 건이 Gateway를 통과하는 경로**와 **endpoint connector의 계약**을 이해하는 것입니다. 기동 과정(Spring 컨텍스트, verticle 배포, 플러그인 로딩)은 2단계 재구성의 기초가 되므로 함께 봅니다.

### 디버깅 환경

1. Gateway를 디버그 모드로 띄웁니다. `run`은 기존 `JAVA_OPTS`에 덧붙이므로 JDWP 옵션을 넘기면 됩니다.
   ```bash
   JAVA_OPTS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005" \
     scripts/gateway-home/gateway-home.sh run
   ```
   기동 과정을 볼 때는 `suspend=y`로 바꿉니다. 그러면 디버거가 붙을 때까지 JVM이 멈춰 기다립니다.
2. IntelliJ에서 **Run → Edit Configurations → + → Remote JVM Debug**를 고르고, 포트를 5005로 해서 Attach합니다.
3. 테스트 백엔드를 띄우고 요청을 보냅니다.
   ```bash
   python3 -m http.server 8081 --bind 127.0.0.1
   curl -i http://localhost:8082/echo/
   ```

참고할 점:
- 플러그인 클래스(`HttpProxyEndpointConnector` 등)는 `plugins/`의 zip에서 별도 classloader로 읽힙니다. 그래도 소스와 빌드가 일치하면 breakpoint가 걸립니다.
- `gravitee-gateway-api`, `gravitee-node` 같은 외부 라이브러리는 IntelliJ의 디컴파일 화면으로 보게 됩니다. 원본 소스로 보려면 엔진 빌드 때 받아 둔 upstream 소스를 "Attach Sources"로 연결하세요. Vert.x는 `~/.m2`에 sources jar가 있습니다.
- 요청 처리는 RxJava 체인입니다. `handle()` 안에서는 체인을 **조립**만 하고 **실행**은 나중에 일어납니다. 실제 동작은 각 컴포넌트의 `execute()`/`connect()` 안쪽에 breakpoint를 걸어 확인합니다.

### breakpoint 경로: 요청 처리

| 순서 | 클래스 | 위치 | 볼 것 |
|---|---|---|---|
| 1 | `HttpProtocolVerticle` | `gravitee-apim-gateway/gravitee-apim-gateway-standalone/gravitee-apim-gateway-standalone-container/.../reactive/standalone/vertx/` | Vert.x HTTP 서버가 요청을 받는 지점 |
| 2 | `DefaultHttpRequestDispatcher` | `gravitee-apim-gateway/gravitee-apim-gateway-reactor/.../reactive/reactor/` | context path(`/echo`)로 API를 찾는 과정 |
| 3 | `DefaultApiReactor` | `gravitee-apim-gateway/gravitee-apim-gateway-handlers/gravitee-apim-gateway-handlers-api/.../reactive/handlers/api/v4/` | `handle()`: 요청 처리 단계(phase) 전체의 순서 |
| 4 | `HttpSecurityChain` (v4) | 같은 모듈 `.../handlers/api/v4/security/` | 플랜 선택과 Keyless 정책 실행 |
| 5 | `FlowChain` (v4) | 같은 모듈 `.../handlers/api/v4/flow/` | flow와 policy가 실행되는 방식 |
| 6 | `HttpEndpointInvoker` | `gravitee-apim-gateway/gravitee-apim-gateway-core/.../reactive/core/v4/invoker/` | endpoint를 고르고 connector를 호출하는 지점 |
| 7 | `DefaultEndpointManager` | 같은 모듈 `.../core/v4/endpoint/` | API 정의의 endpoint를 connector 인스턴스로 만드는 과정 |
| 8 | `HttpProxyEndpointConnector`, `HttpConnector` | `gravitee-apim-plugin/gravitee-apim-plugin-endpoint/gravitee-apim-plugin-endpoint-http-proxy/` | **새 플러그인이 구현할 계약**: `connect(ctx)`에서 요청을 읽고 응답을 채우는 방식 |

### breakpoint 경로: 기동 (`suspend=y`)

| 순서 | 위치 | 볼 것 |
|---|---|---|
| 1 | gravitee-node `SpringBasedContainer` | boot 컨텍스트와 main 컨텍스트 생성, 라이프사이클 컴포넌트 시작 |
| 2 | `GatewayNode.components()` | 컴포넌트 기동 순서 |
| 3 | `VertxEmbeddedContainer.startHttpInstances()` | `"spring:..."` 이름으로 verticle을 배포 |
| 4 | Vert.x `VerticleManager.resolveFactories` → gravitee-node `SpringVerticleFactory.createVerticle` | prefix로 factory를 찾고, Spring prototype 빈으로 verticle 인스턴스를 만듦 |
| 5 | `EndpointConnectorPluginHandler` | `gravitee-apim-plugin/gravitee-apim-plugin-endpoint/gravitee-apim-plugin-endpoint-handler/`. zip 안의 `plugin.properties`가 factory 클래스로 이어지는 과정 |
| 6 | gravitee-plugin `AnnotationBasedPluginContextConfigurer` | service, repository 플러그인이 Spring 자식 컨텍스트로 로드되는 과정 |

### Phase 1에서 답을 찾을 질문

- endpoint connector가 구현해야 하는 interface와 메서드는 무엇인가? (`HttpProxyEndpointConnector`와 `...Factory` 기준)
- API 정의의 endpoint `configuration` JSON이 어떻게 설정 클래스로 바뀌는가? `schema-form.json`의 역할은 무엇인가?
- connector 안에서 요청 헤더, 경로, body를 읽고 바꾸는 API는 무엇인가? 응답 body를 **가로채서 읽는** 방법은 무엇인가? ((d) 사용량 기록에 필요)
- 요청을 거절할 때 쓰는 방법은 무엇인가? (`ctx.interruptWith(...)` 등, (b)에 필요)
- 사용량을 남길 곳은 어디인가? 로그, metrics 추가 필드(`additionalMetrics` 등), 리포터 중에서 정합니다.
- endpoint connector 플러그인은 Spring 컨텍스트 없이 factory로 직접 만들어지는가? (Phase 5의 Spring 결정에 영향)
- (Phase 3 대비) `handlers-shared-policy-group`, `handlers-guardian`, `handlers-cluster`, `dictionary`는 각각 무슨 기능인가?

### 완료 기준

- [ ] 요청 처리 경로를 디버거로 한 번 끝까지 따라감
- [ ] 기동 경로를 디버거로 한 번 끝까지 따라감
- [ ] 위 질문의 답을 `gravitee-apim-gateway/STRUCTURE.md`(또는 별도 문서)에 정리함
- [ ] 새 endpoint 플러그인의 뼈대(클래스 구성, `plugin.properties`, 설정 클래스, 어셈블리)를 설명할 수 있음

---

## Phase 2: LLM endpoint 플러그인 MVP

### 준비

- [ ] Ollama를 설치하고 작은 모델 하나를 받습니다(예: `ollama pull qwen2.5:0.5b`).
- [ ] `curl http://localhost:11434/v1/chat/completions`가 응답하는지 확인합니다.

### 모듈

- 위치: `gravitee-apim-plugin/gravitee-apim-plugin-endpoint/gravitee-apim-plugin-endpoint-llm-openai` (in-repo)
- 구성: `endpoint-http-proxy`와 같습니다. connector, factory, configuration, `plugin.properties`, `schema-form.json`, assembly
- `plugin.properties`: `id=llm-openai`, `type=endpoint-connector`

### 기능 (MVP)

| 기능 | 내용 | 설정 예 |
|---|---|---|
| 중계 | 요청을 provider base URL + 경로로 보내고, 응답의 상태와 body를 그대로 돌려줌 | `baseUrl: http://localhost:11434` |
| (a) 인증 주입 | 클라이언트가 보낸 `Authorization`을 지우고 `Bearer <provider key>`를 붙임. 키는 설정이나 환경 변수에서 읽음 | `apiKey: ${OPENAI_API_KEY}` |
| (b) 경로 고정 | 허용한 경로만 보냄 (`POST /v1/chat/completions`, `GET /v1/models`). 나머지는 OpenAI 오류 형식(`{"error": {...}}`)으로 거절 | 허용 목록은 코드 상수로 시작 |
| (d) 사용량 기록 | 응답 JSON의 `usage.prompt_tokens`, `completion_tokens`, `total_tokens`와 `model`을 기록 | 기록 위치는 Phase 1에서 정함 |

Ollama는 `Authorization` 헤더를 확인하지 않습니다. 그래서 (a)는 Ollama로는 검증되지 않고, WireMock 테스트로 검증합니다.

### 먼저 쓸 테스트 (TDD)

`gravitee-apim-gateway-tests-sdk`(`AbstractGatewayTest`)로 Gateway를 띄우고, WireMock을 가짜 OpenAI 서버로 씁니다. 이 테스트들은 Phase 3과 Phase 5에서 코드를 걷어낼 때 **동작이 유지되는지 확인하는 안전망**이 됩니다.

1. `POST /v1/chat/completions`의 body가 provider로 그대로 가고, provider 응답의 상태와 body가 그대로 돌아온다.
2. provider로 가는 요청에 `Authorization: Bearer <설정한 키>`가 붙는다.
3. 클라이언트가 보낸 `Authorization`은 provider로 전달되지 않는다.
4. `GET /v1/models`는 허용된다.
5. 허용 목록 밖의 경로(예: `POST /v1/files`)는 provider를 호출하지 않고, OpenAI 형식의 오류로 거절된다.
6. 응답에 `usage`가 있으면 토큰 수와 모델이 기록된다.
7. 응답에 `usage`가 없거나 JSON이 아니어도(오류 응답 등) 요청은 실패하지 않고 그대로 전달된다.

### gateway-home 반영

- [ ] `scripts/gateway-home/gateway-home.sh`의 `repo_plugins`에 새 모듈을 추가함
- [ ] `scripts/gateway-home/template/apis/`에 LLM API 예제(`llm-api.json`, 경로 `/llm`)를 추가함
- [ ] `scripts/gateway-home/README.md`를 갱신함

### 완료 기준

- [ ] 위 테스트 7개가 통과함
- [ ] `curl http://localhost:8082/llm/v1/chat/completions -d '{"model": "...", "messages": [...]}'`로 Ollama의 응답을 받음
- [ ] 로그에서 사용량 기록을 확인함
- [ ] 허용 목록 밖의 경로가 거절되는 것을 확인함

---

## Phase 3: 덜 중요한 기능 걷어내기

새 Gateway로 가져갈 범위를 줄이는 단계입니다. 여기서 지운 것은 2단계에서 옮길 필요가 없습니다. 모듈별 분류는 `MODULES.md` 5절을 참고하세요.

규칙은 다음과 같습니다.
- 한 번에 하나씩 지웁니다.
- 지울 때마다 `mvn clean install`(테스트 포함), `gravitee-apim-gateway-integration-tests`, Phase 2 테스트, 그리고 `/echo`와 `/llm`에 대한 curl 스모크 테스트를 돌립니다.
- 모두 통과하면 커밋을 하나 만듭니다.
- 이 단계에서는 패키지명을 바꾸지 않습니다. 패키지명은 2단계에서 다룹니다.

| 순서 | 후보 | 규모 (main Java 줄 수) | 위험도 | 비고 |
|---|---|---|---|---|
| 1 | TCP 지원 (`gateway-tcp`, tcp-proxy entrypoint/endpoint) | 약 240 + 플러그인 | 낮음 | LLM은 HTTP만 씀 |
| 2 | 보안 oauth2와 jwt | 약 400 | 낮음 | keyless와 apikey만 남김 |
| 3 | shared-policy-group, guardian, cluster handler, dictionary | 약 4,100 | 중간 | Phase 1에서 역할을 확인한 뒤 결정 |
| 4 | V2(legacy) 실행 엔진 | 비반응형 패키지 약 53,000 (V4와 공용 코드 포함) | 높음 | 효과가 가장 크지만 공용 코드와 섞여 있음. 테스트를 안전망으로 두고 단계적으로 진행. 2단계로 미뤄도 됨 |
| 5 | 파일 기반 API 로더 단순화 | — | 중간 | `apiEvent` 이중 감싸기 대신 V4 정의 JSON을 바로 읽는 로더를 만듦. `repository-api`(약 29,000줄) 의존을 줄이는 출발점. local sync가 테스트용 모드라서 운영 수준이 필요하면 사실상 필수 |

---

## Phase 4: LLM 기능 확장 (백로그)

Phase 2 이후 필요에 따라 진행합니다. 1단계와 2단계 어느 쪽에서 해도 됩니다.

- 스트리밍(SSE) 중계
- 형식 변환이 필요한 provider (Anthropic 등)
- 여러 provider와 모델 라우팅
- 토큰 사용량 기반 제한 ((d)의 기록이 기반이 됨)
- provider 오류 정규화 ((e))
- 관리용 API, DB

---

# 2단계: 새 Gateway

## Phase 5: gravitee-node 흡수와 축소

### 왜 gravitee-node부터인가

gravitee-node는 Gravitee 제품들이 공통으로 쓰는 서버 런타임 프레임워크입니다(18개 모듈, 약 35,500줄). Gateway의 기동, 설정, Vert.x 생성, 플러그인 로딩, 클러스터와 캐시가 모두 여기에 있습니다. 지금은 외부 라이브러리라서 세 가지 문제가 있습니다.
- 빌드하려면 직접 빌드해서 `~/.m2`에 넣어야 합니다.
- 기동 흐름을 따라가다 보면 코드가 저장소 밖으로 끊깁니다.
- 기동에 필요한 부품(cluster, cache)이 플러그인 zip으로 나뉘어 있습니다.

Gateway에서 `io.gravitee.node.*`를 import하는 `src/main` 파일은 135개입니다. 많이 쓰는 영역은 다음과 같습니다(import 수 기준).
- `api.*` 일반 인터페이스
- `api.license` 66회
- `api.opentelemetry` 55회
- `api.configuration` 54회
- `vertx.client`/`vertx.server` 73회

### 시작 시점

Phase 2가 끝난 뒤 시작합니다. 그때쯤이면 요청 경로와 기동 경로를 이해한 상태이고, Phase 2 테스트와 integration-tests가 안전망으로 있습니다.

### 원칙

- **호환 기간에는 안쪽 구현만 줄이고, 패키지와 인터페이스는 그대로 둡니다.** 외부 정책 zip은 이런 API를 보통 `provided`로 선언하므로, Gateway classpath에 같은 이름의 클래스가 있기만 하면 동작합니다.
- **Gateway 코드와 node 구현 사이에 경계를 둡니다.** Gateway가 `SpringBasedContainer` 같은 구현 클래스를 직접 참조하지 않게 정리합니다. 그래야 Spring 결정을 내릴 때 영향 범위가 `container` 하나로 좁아집니다.

### 모듈별 처리

| 등급 | node 모듈 | 처리 |
|---|---|---|
| 핵심 | `container`(기동과 라이프사이클), `vertx`(서버와 클라이언트 생성), `plugins`, `api`(configuration, server), `certificates`(TLS), `logging` | 가져와서 다듬음 |
| 단순화 | `cache`, `cluster` | 단일 노드 구현만 런타임에 내장. 인터페이스(`ClusterManager`, `CacheManager`)는 호환을 위해 남김 |
| 선택 | `opentelemetry`(약 5,100줄), `monitoring`/`management`(약 5,600줄), `secrets` | 처음엔 빼거나 간단한 health/metrics endpoint로 대체 |
| 제거 | `license`, `kubernetes`, `notifier`, `jetty`, `reporter` | 불필요 |

참고로 `cluster`의 실체는 다음과 같습니다.
- `ClusterManager`가 제공하는 것: 멤버십, primary 노드 판별, 노드 간 Topic과 Queue
- 구현: `standalone`(자기 자신 하나가 항상 primary, Topic과 Queue는 Vert.x 로컬 event bus)과 `hazelcast` 두 가지
- APIM Gateway에서의 사용처: services-sync의 distributed sync에서 `isPrimaryNode()`로만 씁니다. 현재 구성에서는 사실상 기동할 때 존재 확인에만 쓰입니다.
- 주의: `gravitee-apim-gateway-handlers-cluster`의 `ClusterManager`는 Kafka 클러스터 정의를 다루는 별개의 클래스입니다.

### 단계

**A. 흡수**
- [ ] 새 저장소를 만들고, 1단계 결과물(Gateway 모듈, `llm-openai` 플러그인, gateway-home 스크립트, 테스트)을 옮김
- [ ] gravitee-node의 핵심 모듈과 단순화 대상 모듈을 **패키지명 그대로** 내부 모듈로 가져옴
- [ ] `cluster`와 `cache`의 standalone 구현을 내장하고, cluster 플러그인 탐색과 `NoClusterManagerException`을 제거함
- [ ] gateway-home에서 node cluster/cache 플러그인 zip을 뺌
- [ ] 빌드에 `~/.m2`의 gravitee-node가 더 이상 필요 없음을 확인함

**B. 축소 (호환 유지)**
- [ ] `LicenseManager`를 "항상 허용" 구현으로 바꿈 → Gateway 곳곳의 엔터프라이즈 기능 검사를 제거함. 인터페이스는 C까지 남김
- [ ] `kubernetes`, `notifier`, `jetty`, `reporter`(node 수준)를 삭제함
- [ ] `management`와 `monitoring`을 간단한 health/metrics endpoint 하나로 교체함
- [ ] `opentelemetry`를 빼거나 선택 기능으로 분리함
- [ ] cluster의 hazelcast 구현, services-sync의 distributed sync를 삭제함
- [ ] Gateway 코드가 node 구현 클래스(특히 Spring 컨테이너)를 직접 참조하지 않게 경계를 정리함

**C. 호환 끊기 (자체 플러그인 API가 안정된 뒤)**
- [ ] 패키지명을 새 Gateway 이름으로 바꿈
- [ ] `api` 인터페이스 중 쓰지 않는 것과 license 인터페이스를 삭제함
- [ ] Spring을 유지할지 결정함 (유지 / 제거하고 직접 연결)
- [ ] 계속 필요한 외부 정책을 직접 포팅함

### 함께 다룰 외부 라이브러리

플러그인 호환의 실질적인 경계는 node보다 **`gravitee-gateway-api`**(정책과 커넥터가 구현하는 인터페이스)입니다. 아래 라이브러리도 같은 A → B → C 순서로 흡수 여부를 정합니다.

| 라이브러리 | 역할 |
|---|---|
| `gravitee-gateway-api` | 플러그인 공개 API (`EndpointConnector`, `Policy`, `HttpExecutionContext` 등) |
| `gravitee-plugin` | 플러그인 zip 탐색, classloader, 자식 컨텍스트 |
| `gravitee-common`, `gravitee-expression-language` | 공통 유틸, EL |

### 완료 기준

- [ ] 빌드가 공개 Maven Central만으로 됨 (직접 빌드해서 `~/.m2`에 넣는 Gravitee 라이브러리가 없음)
- [ ] 외부 cluster/cache 플러그인 zip 없이 기동함
- [ ] Phase 2 테스트, integration-tests, `/echo`와 `/llm` 스모크 테스트가 통과함
- [ ] 호환 기간에는 Maven Central의 기존 정책 zip(예: `policy-keyless`)이 그대로 동작함

---

## 위험 요소

| 위험 | 내용 | 대응 |
|---|---|---|
| 플러그인 API가 alpha 버전 | `gravitee-gateway-api 7.2.0-alpha.3`에 의존. 1단계에서 upstream을 따라가면 interface가 바뀔 수 있음 | 2단계에서 흡수하면 버전이 고정됨 |
| local sync는 테스트용 모드 | 코드 주석에 "INTERNAL USE ONLY ... not production ready" | Phase 3의 5번 (파일 기반 로더) |
| upstream 버전 상승 (1단계) | 루트 pom의 Gravitee 라이브러리 버전이 바뀌면 `~/.m2`에 그 버전을 다시 빌드해 넣어야 함 (`fresh-clone-build-prompt.md`) | 1단계에서는 upstream을 꼭 필요할 때만 merge |
| V2 제거와 upstream merge | V2를 깊게 지울수록 merge 충돌이 늘어남 | 1단계에서 부담되면 2단계로 미룸 (upstream 추적을 끊은 뒤에는 이 비용이 없음) |
| upstream 추적 중단 후 보안 패치 | Vert.x, Netty, Jackson 같은 서드파티 의존성과 흡수한 Gravitee 코드의 수정을 직접 챙겨야 함 | 새 저장소에 처음부터 의존성 자동 업데이트 도구(Renovate 등)를 붙임 |
| 플러그인 바이너리 호환 | 호환 기간에 흡수한 API의 시그니처를 실수로 바꾸면 기존 정책 zip이 런타임에 깨짐 (`NoSuchMethodError` 등) | Maven Central 정책 zip을 실제로 로드하는 스모크 테스트를 유지 |

## 진행 기록

| 날짜 | 내용 |
|---|---|
| 2026-11-24 | 저장소를 Gateway와 그 의존 모듈만 남기고 정리 (`0f6e379c754`) |
| 2026-11-24 | gateway-home 스크립트 추가 (`2b5d6161444`) |
| 2026-11-24 | 계획 수립: MVP 기능 (a)(b)(d), 대상은 로컬 Ollama (`43c8fa39031`) |
| 2026-11-24 | 모듈 구성 문서 `MODULES.md` 추가 (`b844903ddcf`) |
| 2026-11-24 | 최종 목표(새 Gateway)를 기준으로 계획 재구성. 2단계 결정(upstream 중단, 플러그인 호환 유지 후 단절, 단일 노드, Spring은 추후 결정)과 Phase 5 추가 |

# 나만의 LLM Gateway 계획

이 저장소(`chore/gateway-only` 브랜치)의 Gravitee Gateway를 이해하고, LLM endpoint 플러그인을 직접 만들고, 덜 중요한 모듈을 걷어내 나만의 Gateway로 바꿉니다.

- 작성일: 2026-11-24
- 기준 커밋: `2b5d6161444` (`chore/gateway-only`, upstream `2b0ebc04e76` 기반)

## 확정한 결정

| 항목 | 결정 |
|---|---|
| MVP 기능 | OpenAI 호환 요청 중계 + **(a) provider 인증 주입**, **(b) OpenAI API 경로 고정**, **(d) 사용량(usage) 기록** |
| 연결 대상 | OpenAI 호환 API. 개발과 확인은 **로컬 Ollama**(`/v1`)로 함 |
| 재구성 수준 | **구조 유지, 기능만 걷어내기.** 패키지명과 모듈 구조를 유지해 upstream 수정을 계속 받을 수 있게 함 |
| 설정 관리 | **파일만** 사용 (`gravitee.yml`, `apis/*.json`). DB와 Management API 없음 |
| Phase 1 진행 | 직접 디버거로 따라가고, 막히는 부분은 질문 |

## 배경 사실

- OpenAI 호환 "중계"만 할 거라면 기존 `http-proxy` endpoint로도 됩니다. 그래서 직접 만드는 플러그인은 단순 프록시가 못 하는 (a), (b), (d)를 맡습니다.
- Gravitee에는 `ApiType.LLM_PROXY`가 정의되어 있지만, 이를 처리하는 플러그인(`gravitee-entrypoint-llm-proxy` 등)은 공개 저장소에 없어서 엔터프라이즈 전용으로 보입니다. 직접 만들어야 하고, 참고할 공개 구현이 없습니다.
- Gateway는 entrypoint, endpoint, policy, reactor를 모두 **플러그인 zip**으로 읽습니다. 공개 예제로 `endpoint-http-proxy`(main 코드 약 2,000줄)가 이 저장소에 있습니다.

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

---

## Phase 1: 코드 이해 (직접 디버거로 따라가기)

목표는 **V4 HTTP 요청 한 건이 Gateway를 통과하는 경로**와 **endpoint connector의 계약**을 이해하는 것입니다.

### 디버깅 환경

1. Gateway를 디버그 모드로 띄웁니다. `run`은 기존 `JAVA_OPTS`에 덧붙이므로 JDWP 옵션을 넘기면 됩니다.
   ```bash
   JAVA_OPTS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005" \
     scripts/gateway-home/gateway-home.sh run
   ```
2. IntelliJ에서 **Run → Edit Configurations → + → Remote JVM Debug**를 고르고, 포트를 5005로 해서 Attach합니다.
3. 테스트 백엔드를 띄우고 요청을 보냅니다.
   ```bash
   python3 -m http.server 8081 --bind 127.0.0.1
   curl -i http://localhost:8082/echo/
   ```

플러그인 클래스(`HttpProxyEndpointConnector` 등)는 `plugins/`의 zip에서 별도 classloader로 읽힙니다. 그래도 소스와 빌드가 일치하면 breakpoint가 걸립니다. `gravitee-gateway-api`의 interface(`EndpointConnector` 등)는 외부 라이브러리라 IntelliJ의 디컴파일 화면으로 보게 됩니다.

### breakpoint 경로

| 순서 | 클래스 | 위치 | 볼 것 |
|---|---|---|---|
| 1 | `HttpProtocolVerticle` | `gravitee-apim-gateway/gravitee-apim-gateway-standalone/gravitee-apim-gateway-standalone-container/.../reactive/standalone/vertx/` | Vert.x HTTP 서버가 요청을 받는 지점 |
| 2 | `DefaultHttpRequestDispatcher` | `gravitee-apim-gateway/gravitee-apim-gateway-reactor/.../reactive/reactor/` | context path(`/echo`)로 API를 찾는 과정 |
| 3 | `DefaultApiReactor` | `gravitee-apim-gateway/gravitee-apim-gateway-handlers/gravitee-apim-gateway-handlers-api/.../reactive/handlers/api/v4/` | 요청 처리 단계(phase) 전체의 순서 |
| 4 | `HttpSecurityChain` (v4) | 같은 모듈 `.../handlers/api/v4/security/` | 플랜 선택과 Keyless 정책 실행 |
| 5 | `FlowChain` (v4) | 같은 모듈 `.../handlers/api/v4/flow/` | flow와 policy가 실행되는 방식 |
| 6 | `HttpEndpointInvoker` | `gravitee-apim-gateway/gravitee-apim-gateway-core/.../reactive/core/v4/invoker/` | endpoint를 고르고 connector를 호출하는 지점 |
| 7 | `DefaultEndpointManager` | 같은 모듈 `.../core/v4/endpoint/` | API 정의의 endpoint를 connector 인스턴스로 만드는 과정 |
| 8 | `HttpProxyEndpointConnector` | `gravitee-apim-plugin/gravitee-apim-plugin-endpoint/gravitee-apim-plugin-endpoint-http-proxy/` | **새 플러그인이 구현할 계약**: `connect(ctx)`에서 요청을 읽고 응답을 채우는 방식 |
| 9 | `EndpointConnectorPluginHandler` | `gravitee-apim-plugin/gravitee-apim-plugin-endpoint/gravitee-apim-plugin-endpoint-handler/` | zip 안의 `plugin.properties`가 factory 클래스로 이어지는 과정 |

### Phase 1에서 답을 찾을 질문

- endpoint connector가 구현해야 하는 interface와 메서드는 무엇인가? (`HttpProxyEndpointConnector`와 `...Factory` 기준)
- API 정의의 endpoint `configuration` JSON이 어떻게 설정 클래스로 바뀌는가? `schema-form.json`의 역할은 무엇인가?
- connector 안에서 요청 헤더, 경로, body를 읽고 바꾸는 API는 무엇인가? 응답 body를 **가로채서 읽는** 방법은 무엇인가? ((d) 사용량 기록에 필요)
- 요청을 거절할 때 쓰는 방법은 무엇인가? (`ctx.interruptWith(...)` 등, (b)에 필요)
- 사용량을 남길 곳은 어디인가? 로그, metrics 추가 필드(`additionalMetrics` 등), 리포터 중에서 정합니다.
- (Phase 3 대비) `handlers-shared-policy-group`, `handlers-guardian`, `handlers-cluster`, `dictionary`는 각각 무슨 기능인가?

### 완료 기준

- [ ] 위 경로를 디버거로 한 번 끝까지 따라감
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

`gravitee-apim-gateway-tests-sdk`(`AbstractGatewayTest`)로 Gateway를 띄우고, WireMock을 가짜 OpenAI 서버로 씁니다.

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

## Phase 3: 덜 중요한 모듈 걷어내기

규칙은 다음과 같습니다.
- 한 번에 하나씩 지웁니다.
- 지울 때마다 `mvn clean install`(테스트 포함), `gravitee-apim-gateway-integration-tests`, 그리고 `/echo`와 `/llm`에 대한 curl 스모크 테스트를 돌립니다.
- 모두 통과하면 커밋을 하나 만듭니다.
- 패키지명은 바꾸지 않습니다.

| 순서 | 후보 | 규모 (main Java 줄 수) | 위험도 | 비고 |
|---|---|---|---|---|
| 1 | TCP 지원 (`gateway-tcp`, tcp-proxy entrypoint/endpoint) | 약 240 + 플러그인 | 낮음 | LLM은 HTTP만 씀 |
| 2 | 보안 oauth2와 jwt | 약 400 | 낮음 | keyless와 apikey만 남김 |
| 3 | shared-policy-group, guardian, cluster handler, dictionary | 약 4,100 | 중간 | Phase 1에서 역할을 확인한 뒤 결정 |
| 4 | V2(legacy) 실행 엔진 | 비반응형 패키지 약 53,000 (V4와 공용 코드 포함) | 높음 | 효과가 가장 크지만 공용 코드와 섞여 있음. 테스트를 안전망으로 두고 마지막에 단계적으로 진행 |
| 5 | (선택) 파일 기반 API 로더 단순화 | — | 중간 | `apiEvent` 이중 감싸기 대신 V4 정의 JSON을 바로 읽는 로더를 만듦. `repository-api`(약 29,000줄) 의존을 줄이는 출발점 |

## Phase 4 이후 (지금 범위 밖)

- 스트리밍(SSE) 중계
- 형식 변환이 필요한 provider (Anthropic 등)
- 여러 provider와 모델 라우팅
- 토큰 사용량 기반 제한 ((d)의 기록이 기반이 됨)
- provider 오류 정규화 ((e))
- 관리용 API, DB

## 위험 요소

- **플러그인 API가 alpha 버전**: `gravitee-gateway-api 7.2.0-alpha.3`에 의존합니다. upstream을 따라가면 interface가 바뀔 수 있습니다.
- **local sync는 테스트용 모드**: 코드 주석에 "INTERNAL USE ONLY ... not production ready"라고 적혀 있습니다. 운영 수준이 필요하면 Phase 3의 5번이 사실상 필요합니다.
- **V2 제거와 upstream merge**: V2를 깊게 지울수록 upstream merge 충돌이 늘어납니다. Phase 3의 4번은 효과와 비용을 다시 따져 보고 진행합니다.
- **upstream 버전 상승**: 루트 pom의 Gravitee 라이브러리 버전이 바뀌면 `~/.m2`에 그 버전을 다시 직접 빌드해 넣어야 합니다(`fresh-clone-build-prompt.md` 참고).

## 진행 기록

| 날짜 | 내용 |
|---|---|
| 2026-11-24 | 저장소를 Gateway와 그 의존 모듈만 남기고 정리 (`0f6e379c754`) |
| 2026-11-24 | gateway-home 스크립트 추가 (`2b5d6161444`) |
| 2026-11-24 | 계획 수립: MVP 기능 (a)(b)(d), 대상은 로컬 Ollama |

# 모듈 구성

이 브랜치(`chore/gateway-only`)에 남은 Maven 모듈을 정리한 문서입니다. 각 모듈이 Gateway 빌드에 필요한지, 무슨 일을 하는지 설명합니다.

- 기준: `scripts/gateway-home/gateway-home.sh build`가 실행하는 빌드
- 괄호 안 숫자: 각 모듈의 `src/main/java` 아래 Java 파일 수 (규모를 가늠하는 용도)

## 1. 빌드의 출발점

`gateway-home.sh build`는 아래 6개 모듈을 지정하고 `-am`(also-make)으로 이 모듈들이 의존하는 모듈까지 함께 빌드합니다.

| 지정 모듈 | 결과물 | 이유 |
|---|---|---|
| `gravitee-apim-gateway-standalone-bootstrap` | jar | `main()` 진입점 |
| `gravitee-apim-gateway-standalone-container` | jar | Gateway 본체 조립 (Spring 설정 + Vert.x 서버) |
| `gravitee-apim-plugin-entrypoint-http-proxy` | 플러그인 zip | V4 HTTP 프록시 entrypoint |
| `gravitee-apim-plugin-endpoint-http-proxy` | 플러그인 zip | V4 HTTP 프록시 endpoint |
| `gravitee-apim-repository-noop` | 플러그인 zip | DB 없이 실행 (`type: none`) |
| `gravitee-apim-gateway-services-sync` | 플러그인 zip | API 정의 동기화 (local sync가 여기 있음) |

`-am`을 따라가면 **남은 64개 모듈 중 60개가 빌드에 들어갑니다.** 빠지는 4개는 다음과 같습니다.

| 빌드에서 빠지는 모듈 | 이유 |
|---|---|
| `gravitee-apim-bom` | 다른 프로젝트가 버전을 맞추려고 import하는 BOM. 이 reactor 안에서는 아무도 참조하지 않음 |
| `gravitee-apim-gateway-integration-tests` | 통합 테스트 전용 |
| `gravitee-apim-plugin-entrypoint-tcp-proxy` | TCP 프록시 플러그인. 실행 구성에 포함하지 않음 |
| `gravitee-apim-plugin-endpoint-tcp-proxy` | 위와 같음 |

> `gravitee-apim-gateway-tests-sdk`와 `gravitee-apim-plugin-endpoint-mock`은 런타임에 쓰이지 않습니다. 하지만 `entrypoint-http-proxy`가 tests-sdk를 **test scope**로 의존하고 tests-sdk가 endpoint-mock을 의존하기 때문에 `-am`으로 함께 빌드됩니다. `-DskipTests`는 테스트 실행만 건너뛰고 의존 모듈 빌드는 건너뛰지 않습니다.

## 2. 전체 구조 한눈에 보기

```
                       ┌──────────────── standalone ────────────────┐
                       │ bootstrap(main) → container(Spring+Vert.x)  │
                       └───────────────┬─────────────────────────────┘
                                       │
            ┌──────────────────────────┼───────────────────────────┐
            ▼                          ▼                           ▼
        reactor                 services-sync                 reporting / opentelemetry
   (요청 → API 찾기)           (API 정의 읽기·배포)             (리포트·트레이싱)
            │                          │
            ▼                          ▼
   handlers-api (V2/V4 API 실행: security → flow → invoker)
     ├─ security-*   (플랜 인증: keyless, api-key, jwt, oauth2)
     ├─ flow, policy (flow 선택, policy chain)
     ├─ platform     (organization 단위 flow)
     ├─ resource, dictionary, connector
     └─ core         (ExecutionContext, EndpointInvoker, processor)
            │
            ▼
   http / tcp (Vert.x 요청·응답 어댑터)
            │
            ▼
   plugin-*-handler (플러그인 로딩) ──► 플러그인 zip (entrypoint/endpoint/repository/...)
            │
            ▼
   definition-model/jackson (API 정의 모델) · repository-api (저장소 모델·인터페이스)
   reporter-common · common · gamma-definition-model
```

아래쪽에 있는 모듈일수록 다른 모듈이 많이 의존하는 기반 모듈입니다.

## 3. 모듈별 설명

### 3.1 빌드 설정 (pom 전용)

| 모듈 | 역할 |
|---|---|
| `/` (`gravitee-api-management`) | 루트 reactor. 모듈 목록, 라이선스와 prettier 검증, 외부 Gravitee 라이브러리 버전(`gravitee-node.version` 등) |
| `gravitee-apim-parent` | 모든 모듈이 상속하는 parent. 의존성과 플러그인 버전 관리 |
| `gravitee-apim-bom` | 외부 프로젝트용 BOM. **빌드에 쓰이지 않음** |
| `gravitee-apim-gateway`, `-handlers`, `-security`, `-services`, `-standalone` | 하위 모듈을 묶는 aggregator pom |
| `gravitee-apim-plugin`, `-entrypoint`, `-endpoint`, `-apiservice`, `-reactor` | 위와 같음 |
| `gravitee-apim-definition`, `gravitee-apim-repository`, `gravitee-apim-reporter`, `gravitee-gamma` | 위와 같음 |

### 3.2 기반 모델과 공통 라이브러리

| 모듈 | 역할 |
|---|---|
| `gravitee-apim-definition-model` (214) | **API 정의 모델.** `io.gravitee.definition.model`(V2)과 `.v4`(V4: listener, entrypoint, endpoint group, plan, flow 등). `apis/*.json`의 `definition` 문자열이 이 클래스들로 바뀝니다 |
| `gravitee-apim-definition-jackson` (102) | 정의 모델용 Jackson 직렬화와 역직렬화 (`GraviteeMapper`). V2 정의는 커스텀 deserializer로 읽습니다 |
| `gravitee-apim-repository-api` (486) | **저장소 추상화.** `io.gravitee.repository.management.model.Api`, `Event`, `Plan`, `Subscription` 등의 모델과 `*Repository` 인터페이스. local sync가 읽는 `apiEvent.payload`가 이 모델입니다. Gateway는 일부만 쓰지만 Management API와 공유하는 모듈이라 큽니다 |
| `gravitee-apim-repository-noop` (39) | 모든 Repository 인터페이스를 "빈 결과"로 구현한 플러그인 (`type: none`). DB 없이 기동할 때 사용 |
| `gravitee-apim-reporter-common` (44) | 리포터 공통 코드: 리포트 포매터(JSON/CSV 등), bulk 처리, 압축. 리포터 플러그인이 사용 |
| `gravitee-apim-common` (30) | APIM 공용 유틸. `UseCase`/`DomainService` 마커, 시크릿 암호화(AES-GCM, data key) |
| `gravitee-gamma-definition-model` (22) | Gamma(차세대 관리 플랫폼)의 엔티티와 권한 모델. Gateway에서는 `handlers-api`의 approval 상태 관리(`ApprovalStateManagerImpl` 등)와 `services-sync`가 사용 |

### 3.3 Gateway 실행 진입과 조립

| 모듈 | 역할 |
|---|---|
| `gravitee-apim-gateway-standalone-bootstrap` (1) | `Bootstrap.main()`. `lib/` classpath로 container를 띄우는 진입점 |
| `gravitee-apim-gateway-standalone-container` (10) | **Gateway 조립.** `GatewayNode`(라이프사이클 컴포넌트 목록), `VertxReactorConfiguration`(Spring 빈), `VertxEmbeddedContainer`(verticle deploy), `HttpProtocolVerticle`/`TcpProtocolVerticle`(서버를 열고 요청을 dispatcher로 전달) |
| `gravitee-apim-gateway-env` (6) | `gravitee.yml`의 Gateway 설정 바인딩: 요청 타임아웃, 경로 처리 방식, 클라이언트 인증 등 (`GatewayConfiguration`) |

### 3.4 요청 처리 (data plane의 핵심)

| 모듈 | 역할 |
|---|---|
| `gravitee-apim-gateway-http` (19) | Vert.x `HttpServerRequest`/`Response`를 Gravitee의 `Request`/`Response`로 감싸는 어댑터 (HTTP/1, HTTP/2, gRPC, WebSocket) |
| `gravitee-apim-gateway-tcp` (3) | TCP 소켓 어댑터. `http`, `reactor`, `handlers-api`가 의존해서 빌드에 포함됩니다 |
| `gravitee-apim-gateway-reactor` (85) | **요청 라우팅.** `DefaultHttpRequestDispatcher`가 host와 경로로 API를 찾고(`HttpAcceptorResolver`) 해당 `ReactorHandler`로 넘깁니다. 배포된 API 목록(`ReactorHandlerRegistry`)과 API 배포 이벤트 처리(`ReactorEventListener`)도 이곳에 있습니다 |
| `gravitee-apim-gateway-core` (155) | **실행 엔진의 공통 부품.** `ExecutionContext` 구현, processor chain, condition 평가(EL), `HttpEndpointInvoker`(V4 endpoint 선택과 `connect` 호출), endpoint manager, failover, hook, tracing |
| `gravitee-apim-gateway-handlers-api` (187) | **API 하나를 실행하는 reactor.** V4 `DefaultApiReactor.handle()`(security → flow → invoker → 응답 순서), V2 레거시 `ApiReactorHandler`, 플랜과 구독 검증, API 배포 매니저 |
| `gravitee-apim-gateway-handlers-common` (1) | reactor factory 공통 부모 클래스 (`AbstractReactorFactory`) |
| `gravitee-apim-gateway-flow` (28) | flow 선택 (`BestMatchFlowResolver`, `ConditionalFlowResolver`)과 flow에서 policy 목록 해석 |
| `gravitee-apim-gateway-policy` (75) | **policy 실행.** `PolicyManager`(플러그인 policy 로딩), `HttpPolicyChain`, V2 policy를 V4에서 실행하는 adapter |
| `gravitee-apim-gateway-platform` (26) | organization(플랫폼) 수준 flow. 모든 API 앞뒤에 공통으로 붙는 policy (`OrganizationReactor`) |
| `gravitee-apim-gateway-security-core` (19) | **플랜 인증 프레임워크.** 요청에 맞는 플랜을 고르는 `AuthenticationHandlerSelector`, 토큰 추출, mTLS 구독 인증서 |
| `gravitee-apim-gateway-security-keyless` (1) | Keyless 플랜 handler |
| `gravitee-apim-gateway-security-apikey` (1) | API Key 플랜 handler |
| `gravitee-apim-gateway-security-jwt` (2) | JWT 플랜 handler |
| `gravitee-apim-gateway-security-oauth2` (2) | OAuth2 플랜 handler |
| `gravitee-apim-gateway-resource` (8) | API에 선언한 resource(캐시, OAuth2 서버 등) 로딩과 라이프사이클 |
| `gravitee-apim-gateway-dictionary` (5) | dictionary(환경별 key-value). EL `{#dictionaries[...]}`에서 사용 |
| `gravitee-apim-gateway-connector` (3) | 커넥터 레지스트리 (V2 레거시 HTTP 커넥터 등록) |

### 3.5 부가 reactor (API 이외의 배포 대상)

| 모듈 | 역할 |
|---|---|
| `gravitee-apim-gateway-handlers-shared-policy-group` (19) | 여러 API가 공유하는 policy 묶음 (Shared Policy Group) |
| `gravitee-apim-gateway-handlers-guardian` (14) | Guardian: 요청을 판정하고 차단하는 보호 정책 계층. container가 의존 |
| `gravitee-apim-gateway-handlers-cluster` (5) | Kafka 클러스터 정의 관리. container와 services-sync가 의존 |
| `gravitee-apim-gateway-generic-event` (3) | Gateway 내부 이벤트 버스 (`GenericEventManager`) |

### 3.6 백그라운드 서비스와 운영

| 모듈 | 역할 |
|---|---|
| `gravitee-apim-gateway-services-sync` (174, 플러그인) | **API 정의 동기화.** `repository`(DB 폴링), `distributed`(클러스터 동기화), `kubernetes`(ConfigMap), **`local`**(`apis/` 폴더 감시). 읽은 정의를 reactor에 배포하고 해제합니다. 이 프로젝트는 `local`만 사용 |
| `gravitee-apim-gateway-repository` (3) | Gateway의 저장소 scope 정의와 health probe (management, ratelimit) |
| `gravitee-apim-gateway-reporting` (7) | 요청 metrics와 log를 리포터 플러그인으로 보내는 `ReporterService`, 노드 모니터링, 로그 폭주 방지(`LogGuardService`) |
| `gravitee-apim-gateway-opentelemetry` (3) | OpenTelemetry 트레이싱 설정 (`TracingContext`) |

### 3.7 플러그인 로딩 (handler)과 내장 플러그인

`*-handler` 모듈은 `plugins/`의 zip을 해당 타입으로 등록하는 **로더**이고, 나머지는 실제 **플러그인**입니다.

| 모듈 | 종류 | 역할 |
|---|---|---|
| `gravitee-apim-plugin-entrypoint-handler` (9) | 로더 | entrypoint-connector 플러그인 등록, classloader, connector factory 관리 |
| `gravitee-apim-plugin-endpoint-handler` (9) | 로더 | endpoint-connector 플러그인 등록 (`EndpointConnectorPluginHandler`). **`llm-openai`도 이 로더로 로드됩니다** |
| `gravitee-apim-plugin-apiservice-handler` (9) | 로더 | API service 플러그인(healthcheck, discovery 등) 로더. core가 의존해서 남아 있고, 플러그인 구현체는 이미 제거됨 |
| `gravitee-apim-plugin-reactor-handler` (6) | 로더 | reactor 플러그인 로더. API 타입별 reactor factory를 플러그인으로 추가하는 경로 |
| `gravitee-apim-plugin-entrypoint-http-proxy` (3) | 플러그인 | V4 PROXY API의 HTTP entrypoint. 클라이언트 요청을 그대로 받아 넘깁니다 |
| `gravitee-apim-plugin-endpoint-http-proxy` (13) | 플러그인 | V4 HTTP endpoint. Vert.x HttpClient로 백엔드를 호출합니다 (`HttpProxyEndpointConnector`, `HttpConnector`). **`llm-openai`의 참고 구현** |
| `gravitee-apim-plugin-entrypoint-tcp-proxy` (3) | 플러그인 | TCP entrypoint. **빌드에서 제외** |
| `gravitee-apim-plugin-endpoint-tcp-proxy` (5) | 플러그인 | TCP endpoint. **빌드에서 제외** |
| `gravitee-apim-plugin-endpoint-mock` (3) | 플러그인 | 고정 응답을 주는 mock endpoint. tests-sdk가 사용 |

### 3.8 테스트

| 모듈 | 역할 |
|---|---|
| `gravitee-apim-gateway-tests-sdk` (101) | Gateway를 JVM 안에서 띄워 API를 배포하고 호출하는 테스트 프레임워크 (`AbstractGatewayTest`, `GatewayRunner`). Phase 2 플러그인 테스트에 사용 |
| `gravitee-apim-gateway-integration-tests` (0) | tests-sdk 기반 통합 테스트 모음 (테스트 코드만 있음). **빌드에서 제외** |

## 4. 이 저장소 밖에서 오는 것

### 4.1 라이브러리 (`~/.m2`)
upstream 저장소에서 직접 빌드해서 설치한 Gravitee 라이브러리입니다(`fresh-clone-build-prompt.md` 참고). 주요 라이브러리는 다음과 같습니다.

| 라이브러리 | 역할 |
|---|---|
| `gravitee-node` | 노드 프레임워크: 라이프사이클, Spring 컨텍스트, Vert.x 생성(`VertxFactory`, `SpringVerticleFactory`), 서버 관리, 클러스터와 캐시 API |
| `gravitee-plugin` | 플러그인 시스템 공통: zip 탐색, `plugin.properties` 파싱, 플러그인 classloader |
| `gravitee-gateway-api` | 플러그인이 구현하는 **공개 API**: `EndpointConnector`, `EntrypointConnector`, `Policy`, `HttpExecutionContext` 등 |
| `gravitee-common`, `gravitee-expression-language`, `gravitee-reporter-api`, `gravitee-resource-api`, `gravitee-policy-api` 등 | 공통 유틸, EL, 각 확장 지점의 인터페이스 |

### 4.2 실행할 때 필요한 외부 플러그인 zip
`gateway-home.sh assemble`이 `plugins/`에 넣는 외부 플러그인입니다.

| 플러그인 | 출처 | 역할 |
|---|---|---|
| `gravitee-node-cluster-plugin-standalone` | `~/.m2` | 단일 노드 클러스터 매니저 (없으면 `NoClusterManagerException`) |
| `gravitee-node-cache-plugin-standalone` | `~/.m2` | 로컬 캐시 |
| `gravitee-policy-keyless` 5.0.0 | Maven Central | Keyless 플랜의 policy 구현 |

## 5. 정리 관점에서 본 분류

`docs/PLAN.md` Phase 3에서 참고할 분류입니다. 지금은 대부분이 다른 모듈의 컴파일 의존성이라 바로 지울 수는 없습니다.

| 분류 | 모듈 |
|---|---|
| **LLM 게이트웨이에 꼭 필요** | standalone-*, env, http, reactor, core, handlers-api, handlers-common, flow, policy, security-core, security-keyless(또는 api-key), services-sync, plugin-entrypoint/endpoint-handler, entrypoint/endpoint-http-proxy, definition-*, repository-api, repository-noop, generic-event |
| **필요하지만 줄일 여지가 있음** | repository-api(Gateway가 쓰는 일부만 필요), handlers-api 안의 V2 레거시 코드, reporting, opentelemetry, platform, resource |
| **제거 후보 (의존성 정리 필요)** | tcp, entrypoint/endpoint-tcp-proxy, security-jwt/oauth2, handlers-shared-policy-group, handlers-guardian, handlers-cluster, dictionary, connector, apiservice-handler, reactor-handler, gamma-definition-model |
| **빌드에서 이미 제외** | bom, integration-tests, tcp-proxy 플러그인 2개 |

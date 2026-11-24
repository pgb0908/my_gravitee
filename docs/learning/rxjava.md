# Gravitee를 읽기 위한 RxJava 학습 정리

Gravitee Gateway 코드를 읽는 데 **필요한 만큼만** 정리한 학습 목록입니다.

- 버전: **RxJava 3.1** (`rxjava-3.1.12.jar`)
- Vert.x의 RxJava 바인딩: **`vertx-rx-java3` 5.0** (`io.vertx.rxjava3.*`)
- 숫자는 `gravitee-apim-gateway`와 `gravitee-apim-plugin`의 `src/main` 기준 사용 횟수입니다. `map`, `filter`, `collect` 같은 이름은 Java Stream과 섞여 세어졌으니 대략적인 값으로 보세요.

## 0. 한 문장 요약

Gravitee에서 요청 하나의 처리는 **"`Completable` 수십 개를 순서대로 이어 붙인 체인"**입니다. 이 체인은 **조립할 때 아무것도 실행되지 않고, 구독(subscribe)할 때 비로소 실행됩니다.** 이 한 가지를 이해하면 코드의 절반이 읽힙니다.

## 1. 가장 먼저 잡아야 할 개념: 조립과 실행은 따로 일어난다 (lazy)

```java
Completable c = Completable.fromRunnable(() -> System.out.println("실행!"));
// 여기까지는 아무것도 출력되지 않음 (조립만 함)
c.subscribe();   // 이때 "실행!" 출력
```

Gravitee의 `DefaultApiReactor.handleRequest()`가 바로 이 구조입니다.
- 이 메서드는 `.chainWith(...)`를 30번 넘게 호출하는데, 그 순간에는 **체인을 만들기만** 합니다. 보안 검사도 flow 실행도 일어나지 않습니다.
- 실제 실행은 dispatcher가 이 `Completable`을 subscribe할 때 시작됩니다.

**디버깅할 때 중요한 결과**
- `.chainWith(httpSecurityChain.execute(ctx))` 줄에 breakpoint를 걸면 **조립 시점**에 한 번 멈춥니다. 이때 `execute(ctx)`는 "나중에 실행할 `Completable`을 만들어 반환"할 뿐입니다.
- 실제 동작을 보려면 `Completable.defer(() -> { ... })`, `fromRunnable`, `flatMap` 같은 **람다 안쪽**에 breakpoint를 거세요.
- 예: `FlowChain.execute()`는 전체가 `Completable.defer(...)`로 감싸여 있어서, 람다 안쪽은 실행 시점에만 들어갑니다.

## 2. 학습 우선순위

| 순위 | 주제 | Gravitee 사용량 | 왜 필요한가 |
|---|---|---|---|
| ★1 | **lazy 실행, `defer`** | `defer` 75 | 위 0~1절. 모든 것의 기초 |
| ★2 | **5가지 타입: `Completable`, `Maybe`, `Single`, `Flowable`** (+ `Observable`) | import: Completable 155, Maybe 80, Flowable 79, Single 21 | 메서드 시그니처를 읽는 데 필수 |
| ★3 | **순차 연결: `andThen`, `flatMap*`, `concatMapCompletable`** | andThen 131, flatMap 113, concatMapCompletable 27 | 요청 파이프라인이 연결되는 방식 |
| ★4 | **오류 처리: `error`, `onErrorResumeNext`, `onErrorComplete`** | error 208, onErrorResumeNext 56 | 정책 중단(interrupt)과 오류 응답의 흐름 |
| ★5 | **`Flowable<Buffer>`로 body 다루기** | `chunks()` 25, `body()` 17, `onBody`/`onChunks` | (d) 사용량 기록 구현에 직접 필요 |
| 6 | 생성: `just`, `empty`, `complete`, `fromCallable`, `fromRunnable`, `fromIterable`, `create` | 각각 수십 | 체인의 출발점 |
| 7 | 부수효과: `doOnSubscribe`, `doOnSuccess`, `doOnComplete`, `doOnError`, `doFinally`, `doOnDispose` | 합계 약 200 | 메트릭, 로그, 정리 작업 |
| 8 | 조합: `compose`와 Transformer | compose 46 | `CompletableReactorChain.chainWith(transformer)` |
| 9 | 스레드: `subscribeOn`, `observeOn`, `Schedulers.io()`, Vert.x event loop | subscribeOn 25 | blocking 작업을 event loop 밖으로 빼는 곳 |
| 10 | 취소: `Disposable`, `doOnDispose` | 약 20 | 클라이언트가 끊으면 체인이 dispose됨 |
| 11 | `timeout`, `retry`, `buffer`, `groupBy`, `rebatchRequests` | 각각 3~60 | 주로 services-sync. 만났을 때 찾아봐도 충분 |

## 3. 주제별로 알아야 할 것

### ★2. 5가지 타입

| 타입 | 결과 | Gravitee에서의 뜻 | 예 |
|---|---|---|---|
| `Completable` | 완료 또는 오류 (값 없음) | **"이 단계를 실행해라"** | `FlowChain.execute()`, `EndpointConnector.connect()`, `HttpSecurityChain.execute()` |
| `Maybe<T>` | 값 0개 또는 1개, 또는 오류 | "있을 수도 없을 수도" | `request.body()` (body가 없을 수 있음), 플랜 선택 결과 |
| `Single<T>` | 값 정확히 1개, 또는 오류 | "반드시 하나" | Vert.x `httpClient.rxRequest()`, `rxSend()` |
| `Flowable<T>` | 값 0~N개, 또는 오류 (backpressure 지원) | **스트림** | `request.chunks()`(body 조각), 해석된 flow 목록, sync 이벤트 |
| `Observable<T>` | 0~N개 (backpressure 없음) | 거의 안 씀 (import 2) | — |

**읽는 요령:** 메서드가 `Completable`을 반환하면 "부수효과를 내는 단계"이고, `Maybe`/`Single`/`Flowable`을 반환하면 "값을 만들어 내는 단계"입니다.

### ★3. 순차 연결

| 연산자 | 뜻 | Gravitee 예 |
|---|---|---|
| `a.andThen(b)` | a가 **완료되면** b 실행 (Completable → 무엇이든) | `CompletableReactorChain.chainWith()`의 실체 |
| `single.flatMap(x -> ...)` | 값을 받아 **다음 비동기 작업**으로 이어짐 | `HttpConnector.connect()`: 요청 획득 → 전송 → 응답 |
| `flowable.concatMapCompletable(x -> ...)` | 각 요소마다 Completable을 **하나씩 순서대로** 실행 | `FlowChain`: flow를 하나씩 순서대로 실행 |
| `flatMapCompletable` | 위와 같지만 **동시에** 실행할 수 있음 (순서 보장 없음) | 순서가 중요하지 않은 곳 |
| `flatMapMaybe`, `flatMapSingle` | 결과 타입만 다른 flatMap | — |
| `ignoreElement(s)` | 값을 버리고 Completable로 바꿈 | `request.chunks().ignoreElements()`: body를 소비만 함 |
| `map` | 값을 **동기적으로** 변환 | — |

**`map`과 `flatMap`의 차이**가 핵심입니다. `map`은 값을 값으로 바꾸고, `flatMap`은 값을 받아 **다음 비동기 작업(Single/Maybe/Completable)으로 이어 줍니다.**

**`concatMap`과 `flatMap`의 차이**도 중요합니다. 정책과 flow는 순서가 중요하므로 `concatMapCompletable`을 씁니다.

예시: `gravitee-apim-gateway/gravitee-apim-gateway-handlers/gravitee-apim-gateway-handlers-api/src/main/java/io/gravitee/gateway/reactive/handlers/api/v4/flow/FlowChain.java`
```java
public Completable execute(HttpExecutionContext ctx, ExecutionPhase phase) {
    return Completable.defer(() -> {                       // 실행 시점에만 람다 진입
        ...
        return resolvedFlows                               // Flowable<Flow>
            .concatMapCompletable(flow -> executeFlowIfConditionMatches(ctx, flow, phase, executedFlows))  // 하나씩 순서대로
            .andThen(Completable.defer(() -> interruptIfNoFlowExecuted(...)));                            // 다 끝나면
    }).doOnComplete(() -> ctx.removeInternalAttribute(ATTR_INTERNAL_FLOW_STAGE));
}
```

### ★4. 오류 처리

**알아야 할 것**
- 체인 중간에서 오류가 나면 **이후 단계는 건너뛰고** 오류가 아래로 전파됩니다. 가장 가까운 오류 처리 연산자에서 잡힙니다.
- `Completable.error(e)`: 오류로 끝나는 단계를 만듭니다.
- `onErrorResumeNext(e -> 다른 Completable)`: 오류를 받아 **다른 흐름으로 이어 갑니다.**
- `onErrorComplete()`: 오류를 삼키고 정상 완료로 바꿉니다.
- `doOnError`: 오류를 보기만 하고(로그 등) 전파는 그대로 합니다.

**Gravitee에서 볼 곳**
- **정책의 `ctx.interruptWith(...)`는 내부적으로 특수한 오류를 발생시킵니다.** 그래서 이후 flow와 endpoint 호출이 건너뛰어집니다.
  - 실제 코드: `AbstractExecutionContext.interruptWith()`가 `Completable.error(new InterruptionFailureException(executionFailure))`를 반환합니다.
  - 위치: `gravitee-apim-gateway/gravitee-apim-gateway-core/src/main/java/io/gravitee/gateway/reactive/core/context/AbstractExecutionContext.java:105`
- `DefaultApiReactor`의 `.chainWithOnError(error -> processThrowable(ctx, error))`가 그 오류를 잡아 오류 응답으로 바꿉니다. 이 메서드는 `onErrorResumeNext`를 감싼 것입니다.
- `DefaultApiReactor`는 `chainWithOnError`를 여러 번 둬서, "어디까지는 오류가 나도 계속 실행할지"를 나눕니다. 예를 들어 organization의 RESPONSE flow는 오류나 타임아웃이 있어도 항상 실행됩니다.
- (b) 경로 고정에서 허용하지 않는 요청을 거절할 때 이 메커니즘을 씁니다.

### ★5. body를 `Flowable<Buffer>`로 다루기

**알아야 할 것**
- HTTP body는 한 번에 오지 않고 **조각(chunk)으로 흘러옵니다.** Gravitee는 이걸 `Flowable<Buffer>`로 표현합니다.
- `request.chunks()` / `response.chunks(flowable)`: 스트림 그대로 다룹니다.
  - 메모리를 적게 쓰고 스트리밍에 맞습니다.
  - **"다른 곳에 넘겨줄 스트림"을 설정하는 것**이지, 그 자리에서 읽는 게 아닙니다. 나중에 누군가 구독할 때 흘러갑니다.
- `request.body()` / `onBody(...)`: 조각을 **모아서 하나의 `Buffer`**(`Maybe<Buffer>`)로 다룹니다. 전체 JSON을 파싱할 때 씁니다.
- 스트림은 **한 번만 소비할 수 있습니다.** 읽고 나면 다시 채워 넣어야 다음 단계가 받을 수 있습니다. `onBody`/`onChunks`는 "읽고 변환해서 다시 넣기"를 해 주는 헬퍼입니다.

**Gravitee에서 볼 곳**
- `gravitee-apim-plugin/gravitee-apim-plugin-endpoint/gravitee-apim-plugin-endpoint-http-proxy/src/main/java/io/gravitee/plugin/endpoint/http/proxy/connector/HttpConnector.java`
  - 404행 `httpClientRequest.rxSend(request.chunks().map(...))`: 클라이언트 요청 body 스트림을 그대로 백엔드로 보냅니다.
  - 212행 `response.chunks(getEndpointResponseChunks(...))`: 백엔드 응답 스트림을 Gateway 응답에 연결합니다.

**(d) 사용량 기록과의 관계:** 응답 JSON의 `usage`를 읽으려면 응답 body를 가로채야 합니다. 방법은 두 가지입니다.
1. `onBody`로 전체를 모아 파싱하고 다시 넣는 방식: 단순하지만 스트리밍이 안 됩니다.
2. `chunks`에 `doOnNext`/`doOnComplete`를 끼워 흘려보내면서 관찰하는 방식: 스트리밍(SSE)에 맞습니다.

MVP는 1번, Phase 4의 SSE는 2번이 자연스럽습니다.

### 7. 부수효과 연산자 (`doOn*`)

- 흐름을 바꾸지 않고 **특정 시점에 코드를 끼워 넣습니다.** 로그, 메트릭, 정리 작업에 씁니다.
- `doOnSubscribe`(시작), `doOnSuccess`/`doOnComplete`(성공), `doOnError`(실패), `doFinally`(어떻게든 끝남), `doOnDispose`(취소됨)
- 예: `DefaultApiReactor`
  - `.doOnSubscribe(d -> pendingRequests.incrementAndGet())`: 처리 중인 요청 수를 셉니다.
  - `.doOnDispose(...)`: 클라이언트가 연결을 끊었을 때 처리합니다.

### 8. `compose`와 `CompletableReactorChain`

- `compose(transformer)`: "체인을 받아 체인을 돌려주는 함수"를 끼워 넣습니다. 재사용할 수 있는 연산자 묶음입니다.
- Gravitee의 `CompletableReactorChain`은 RxJava를 감싼 **얇은 래퍼**입니다. `chainWith`, `chainWithOnError`, `chainWithIf`라는 이름만 새로 붙였습니다.
  - 위치: `gravitee-apim-gateway/gravitee-apim-gateway-handlers/gravitee-apim-gateway-handlers-api/src/main/java/io/gravitee/gateway/reactive/handlers/api/v4/CompletableReactorChain.java`

  | Gravitee | RxJava 실체 |
  |---|---|
  | `chainWith(Completable)` | `andThen` |
  | `chainWith(CompletableTransformer)` | `compose` |
  | `chainWithOnError(fn)` | `onErrorResumeNext` |
  | `chainWithIf(supplier, cond)` | 조건이 참일 때만 `andThen` |

### 9. 스레드: Vert.x event loop와 Schedulers

**알아야 할 것**
- RxJava 연산자는 기본적으로 **호출한 스레드에서 그대로** 실행됩니다. Gateway에서는 대부분 **Vert.x event loop 스레드**입니다.
- **event loop에서 blocking 작업(파일 I/O, 동기 DB 호출, `Thread.sleep`)을 하면 안 됩니다.** 그 event loop에 묶인 모든 요청이 멈춥니다. Vert.x는 이때 `Thread blocked` 경고를 남깁니다.
- `subscribeOn(Schedulers.io())`: 구독(시작) 작업을 I/O 스레드 풀에서 하게 합니다.
- `observeOn(scheduler)`: 그 지점 **이후**를 다른 스레드에서 하게 합니다.
- Vert.x의 `RxHelper.scheduler(vertx)`: Vert.x event loop를 RxJava Scheduler로 씁니다.

**Gravitee에서 볼 곳**
- 요청 처리 경로는 거의 event loop에서 실행되고, `Schedulers`는 주로 기동, 배포, sync 같은 곳에 나옵니다.
  - `AbstractApiReactor:190`과 `SyncApiReactor:581`의 `.observeOn(Schedulers.io())`
- **새 플러그인 규칙:** `connect()` 안에서 blocking 호출을 하지 마세요. HTTP 호출은 Vert.x `HttpClient`의 `rx*` 메서드를 씁니다.

### 10. Vert.x RxJava 바인딩 (`io.vertx.rxjava3.*`)

- Vert.x API의 콜백/Future를 RxJava 타입으로 바꾼 버전입니다. 메서드 이름 앞에 `rx`가 붙습니다.
  - `HttpClient.request(...)` → `rxRequest(...)`가 `Single<HttpClientRequest>`를 반환
  - `rxSend(...)`가 `Single<HttpClientResponse>`를 반환
  - `HttpClientResponse.toFlowable()`이 `Flowable<Buffer>`(응답 body 스트림)를 반환
- Gateway에서 많이 쓰는 것: `HttpClient` 54, `Vertx` 33, `HttpClientRequest` 31 (import 수)
- `getDelegate()`: rx 래퍼 안의 원래 Vert.x 객체를 꺼냅니다.

## 4. 공부하지 않아도 되는 것 (또는 나중에)

| 주제 | 이유 |
|---|---|
| `Observable` 중심 API, Subject(`PublishSubject` 등) | 거의 안 씀 (Subject는 2곳) |
| 복잡한 결합 연산자 (`zip`, `combineLatest`, `switchMap`, `window`, `amb`) | 각각 0~1곳 |
| Hot/Cold observable 심화, `publish`/`refCount`/`share` | 1곳 |
| 커스텀 연산자 작성 (`lift`) | 없음 |
| Project Reactor (`Mono`/`Flux`) | 쓰지 않음. 개념은 비슷하지만 이름이 다르니 자료를 찾을 때 섞이지 않게 주의 |
| Kotlin Coroutines, CompletableFuture 심화 | 해당 없음 |

## 5. 학습 순서 제안 (약 2~3일)

1. **개념 (반나절):** ReactiveX 공식 사이트(reactivex.io)의 "Introduction"과 RxJava 위키의 "What's different in 3.0"을 읽습니다.
   - lazy, subscribe, 5가지 타입을 익힙니다.
   - marble diagram(구슬 그림) 읽는 법을 익혀 두면 연산자 문서를 빠르게 읽을 수 있습니다.
2. **연산자 (하루):** 2절 표의 ★ 연산자만 marble diagram과 함께 봅니다. 각 연산자로 5줄짜리 JUnit 테스트를 써 봅니다. `TestObserver`(`.test().assertComplete()`)를 쓰면 쉽습니다.
3. **실습 하나:** `Flowable.fromIterable(List.of("a","b","c"))`에 `concatMapCompletable`로 "각 요소마다 로그를 찍고, `b`에서 오류를 내는" 체인을 만듭니다. 그런 다음 `onErrorResumeNext`로 오류를 잡아 봅니다. 이 실습이 `FlowChain`과 `interruptWith`의 축소판입니다.
4. **Gravitee 코드로 확인:** `DefaultApiReactor.handleRequest()`를 위에서 아래로 읽으며 각 `chainWith`가 "어떤 단계를 이어 붙이는지"를 한 줄씩 적어 봅니다. `CompletableReactorChain`의 이름 대응표를 옆에 두고 보세요.
5. **디버거로 확인:** 다음 세 곳에 breakpoint를 걸고 `curl` 한 번에 어떤 순서로 멈추는지 봅니다. 조립 시점과 실행 시점이 다르다는 것을 눈으로 확인하는 실습입니다.
   - `FlowChain.execute()`의 `return Completable.defer(` 줄 (조립 시점)
   - 같은 메서드의 `defer` 람다 안쪽 첫 줄 (실행 시점)
   - `HttpConnector.connect()`

## 6. 이해도 점검 질문

- [ ] `handleRequest()`가 반환된 시점에 보안 검사는 실행되었는가? 언제 실행되는가?
- [ ] `FlowChain`이 `flatMapCompletable`이 아니라 `concatMapCompletable`을 쓰는 이유는?
- [ ] 정책이 `interruptWith`를 호출하면 endpoint 호출(`invokeBackend`)이 왜 건너뛰어지는가?
- [ ] 클라이언트가 응답을 받기 전에 연결을 끊으면 체인에서 어떤 일이 일어나는가? (`doOnDispose`)
- [ ] `response.chunks(...)`를 호출한 시점에 백엔드 응답 body는 이미 다 읽혔는가?
- [ ] (d) 사용량 기록을 위해 응답 body의 `usage`를 읽되, 클라이언트에게도 같은 body를 그대로 보내려면 어떻게 해야 하는가?
- [ ] `connect()` 안에서 파일을 동기적으로 읽으면 어떤 문제가 생기는가?

# Gravitee를 읽기 위한 Spring 학습 정리

Gravitee Gateway 코드를 읽는 데 **필요한 만큼만** 정리한 학습 목록입니다. Spring 전체를 배우려는 문서가 아닙니다.

- 버전: **Spring Framework 6.2** (`spring-context-6.2.19.jar`)
- **Spring Boot는 쓰지 않습니다.** Gateway와 플러그인의 main 코드에 `org.springframework.boot` import가 하나도 없습니다. 그래서 `@SpringBootApplication`, auto-configuration, `application.yml`, starter 같은 Boot 개념은 **공부하지 않아도 됩니다.**
- Spring MVC, WebFlux, Spring Data, Spring Security도 쓰지 않습니다. HTTP는 Vert.x가, 요청 처리는 RxJava가 맡습니다.
- 숫자는 `gravitee-apim-gateway`, `gravitee-apim-plugin`, `repository-noop`의 `src/main` 기준 사용 횟수입니다.

## 0. 한 문장 요약

Gravitee에서 Spring은 **"기동할 때 객체를 만들어 서로 연결하고(DI), 설정값을 넣어 주는 일"**만 합니다. 요청을 처리하는 동안에는 등장하지 않습니다.

## 1. 학습 우선순위

| 순위 | 주제 | Gravitee 사용량 | 왜 필요한가 |
|---|---|---|---|
| ★1 | `@Configuration` + `@Bean` (Java config) | `@Bean` 263, `@Configuration` 34 | Gateway의 **거의 모든 객체**가 이 방식으로 만들어짐 |
| ★2 | 의존성 주입: 생성자/메서드 파라미터 주입, `@Autowired`, `@Qualifier` | `@Qualifier` 89, `@Autowired` 46 | 같은 타입의 빈이 여러 개라 이름으로 구분하는 곳이 많음 |
| ★3 | `ApplicationContext`, `AnnotationConfigApplicationContext` | `ApplicationContext` import 29 | 기동 구조와 플러그인 컨텍스트를 이해하는 핵심 |
| ★4 | `Environment`, `@Value("${...}")` | `@Value` 56, `Environment` 12 | `gravitee.yml` 값이 코드로 들어오는 경로 |
| 5 | `@Import` | 6 | 모듈별 설정 클래스를 하나로 묶는 방식 |
| 6 | 빈 스코프: singleton(기본)과 `@Scope(PROTOTYPE)` | 2 | verticle을 인스턴스 수만큼 만드는 방식 |
| 7 | 부모-자식 컨텍스트 | gravitee-node, gravitee-plugin 내부 | 플러그인 격리 방식 |
| 8 | `@Conditional`, `Condition` | 20 | 설정에 따라 빈을 켜고 끄는 곳 |
| 9 | `@Lazy`, `@Primary`, `@DependsOn`, `@PostConstruct`, `InitializingBean`, `ApplicationContextAware` | 각각 1~10 | 가끔 나옴. 만났을 때 찾아봐도 충분 |
| 10 | `ResolvableType` | 9 | 제네릭 타입으로 빈을 찾을 때. 만났을 때 찾아봐도 충분 |

**★ 4개만 확실히 알면 Gateway 코드의 Spring 부분은 대부분 읽힙니다.**

## 2. 주제별로 알아야 할 것

### ★1. `@Configuration` + `@Bean`

**알아야 할 것**
- `@Configuration` 클래스 안의 `@Bean` 메서드 하나가 **빈 하나**를 정의합니다. 메서드 이름이 기본 빈 이름이 됩니다.
- `@Bean` 메서드의 **파라미터**는 Spring이 다른 빈을 찾아서 넣어 줍니다. Gravitee는 이 방식을 가장 많이 씁니다.
- 빈은 기본적으로 **singleton**입니다. 컨텍스트 안에 하나만 만들어지고 모두 같은 객체를 공유합니다.
- `static @Bean`은 설정 클래스 인스턴스보다 먼저 만들어져야 하는 빈에 씁니다. 예: `StandaloneConfiguration.gatewayConfiguration()`

**Gravitee에서 볼 곳**
- 모듈마다 `.../spring/XxxConfiguration.java`가 있습니다.
  - `ReactorConfiguration`, `ApiHandlerConfiguration`, `PolicyConfiguration` 등
- 예시: `gravitee-apim-gateway/gravitee-apim-gateway-standalone/gravitee-apim-gateway-standalone-container/src/main/java/io/gravitee/gateway/standalone/vertx/VertxReactorConfiguration.java`
  ```java
  @Bean
  @Scope(ConfigurableBeanFactory.SCOPE_PROTOTYPE)
  public HttpProtocolVerticle graviteeVerticle(
      ServerManager serverManager,                                            // 다른 빈을 파라미터로 주입
      @Qualifier("httpRequestDispatcher") HttpRequestDispatcher requestDispatcher
  ) {
      return new HttpProtocolVerticle(serverManager, requestDispatcher);
  }
  ```

**읽는 요령:** "이 객체는 어디서 만들어지지?"가 궁금하면 그 **타입을 반환하는 `@Bean` 메서드**를 찾으세요. IntelliJ에서는 클래스의 생성자에서 *Find Usages*를 하면 대부분 `XxxConfiguration`이 나옵니다.

### ★2. 의존성 주입과 `@Qualifier`

**알아야 할 것**
- 주입 방식 세 가지: 생성자 주입, `@Bean` 메서드 파라미터 주입, 필드 `@Autowired`
- **같은 타입의 빈이 둘 이상이면** Spring이 하나를 고르지 못해 오류가 납니다. 그래서 `@Qualifier("이름")`으로 지정하거나, `@Primary`로 기본값을 정합니다.
- `List<T>` 타입으로 주입받으면 그 타입의 빈이 **전부** 들어옵니다.
- `Optional`이나 `@Autowired(required = false)`는 "없어도 된다"는 뜻입니다.

**Gravitee에서 볼 곳**
- `@Qualifier`가 89번 나옵니다. 예를 들어 `"httpRequestDispatcher"`와 `"tcpSocketDispatcher"`처럼 역할은 비슷하지만 다른 빈을 이름으로 구분합니다.
- 빈 이름은 `@Bean` 메서드 이름이거나 `@Bean("이름")`입니다. `@Qualifier`의 문자열로 검색하면 정의를 찾을 수 있습니다.

### ★3. `ApplicationContext`와 기동

**알아야 할 것**
- `ApplicationContext` = **빈 컨테이너.** 빈 정의를 등록하고 `refresh()`하면 빈이 생성되고 연결됩니다.
- `AnnotationConfigApplicationContext`: `@Configuration` 클래스를 `register()`한 뒤 `refresh()`하는 구현체입니다. Spring Boot 없이 Spring을 쓰는 가장 기본적인 방식입니다.
- `context.getBean(Class)`: 컨테이너에서 빈을 직접 꺼냅니다.
- `ApplicationContextAware`: 빈이 자기를 담고 있는 컨텍스트를 받는 방법입니다.

**Gravitee에서 볼 곳**
- gravitee-node `SpringBasedContainer`(외부 라이브러리)가 기동 순서를 맡습니다.
  1. boot 컨텍스트를 만듭니다.
  2. main 컨텍스트를 만들고 `StandaloneConfiguration`을 등록한 뒤 `refresh()`합니다.
  3. `GatewayNode.components()`의 `LifecycleComponent`를 `getBean()`으로 꺼내 순서대로 `start()`합니다.
- gravitee-node `SpringVerticleFactory`: `ApplicationContextAware`로 컨텍스트를 받고, `getBean(verticleClass)`로 verticle을 만듭니다.

**중요:** `start()`/`stop()` 라이프사이클은 Spring이 아니라 **gravitee-node의 `LifecycleComponent`** 개념입니다. Spring은 객체를 만들고 연결하는 일까지만 합니다.

### ★4. `Environment`와 `@Value`

**알아야 할 것**
- `@Value("${http.port:8082}")`: 설정 키 `http.port`의 값을 넣고, 없으면 `:` 뒤의 기본값을 씁니다.
- `Environment.getProperty("key", Type.class, default)`: 코드에서 직접 읽는 방식입니다.
- property source: 설정값의 출처입니다. 여러 출처가 우선순위대로 쌓입니다.

**Gravitee에서 볼 곳**
- `gravitee.yml`은 Spring이 읽는 게 아니라 **gravitee-node가 읽어서 `Environment`의 property source로 올립니다.**
  - 그래서 YAML의 중첩 키를 `services.sync.local.enabled`처럼 점으로 이은 형태로 씁니다.
  - 환경 변수(`GRAVITEE_HTTP_PORT` 같은 형식)와 시스템 속성(`-Dhttp.port=...`)으로도 덮어쓸 수 있습니다.
- 예: `VertxEmbeddedContainer`의 `@Value("${http.instances:0}")`, `VertxReactorConfiguration.getServerType()`의 `environment.getProperty(...)`

### 5. `@Import`

- 다른 `@Configuration` 클래스를 함께 등록합니다.
- 기동의 루트는 `StandaloneConfiguration`의 `@Import` 목록입니다. 17개 모듈의 설정 클래스가 여기 모여 있어서 **Gateway의 전체 부품 목록**이 됩니다.
  - 위치: `gravitee-apim-gateway/gravitee-apim-gateway-standalone/gravitee-apim-gateway-standalone-container/src/main/java/io/gravitee/gateway/standalone/spring/StandaloneConfiguration.java`
- **Phase 3에서 모듈을 지울 때 가장 먼저 손대는 곳입니다.**

### 6. 빈 스코프

- `singleton`(기본): 컨텍스트당 하나
- `prototype`: `getBean()`을 부를 때마다 새로 만듦
- Gravitee 사용처는 두 곳뿐입니다. `HttpProtocolVerticle`, `TcpProtocolVerticle`이 prototype입니다. Vert.x가 CPU 코어 수만큼 verticle 인스턴스를 만들어야 하기 때문입니다.

### 7. 부모-자식 컨텍스트 (플러그인 격리)

**알아야 할 것**
- 자식 컨텍스트는 **부모의 빈을 볼 수 있지만, 부모는 자식의 빈을 볼 수 없습니다.**
- 컨텍스트마다 다른 classloader를 쓸 수 있습니다.

**Gravitee에서 볼 곳**
- gravitee-plugin `AnnotationBasedPluginContextConfigurer`(외부 라이브러리)
  - 플러그인마다 **별도 classloader**를 둔 `AnnotationConfigApplicationContext`를 만들고, Gateway 메인 컨텍스트의 자식으로 붙입니다.
- 대상은 service, repository 플러그인입니다.
  - `services-sync`의 `SyncConfiguration`, `LocalSyncConfiguration`
  - `repository-noop`의 `NoOp*RepositoryConfiguration`
- 이 플러그인들 안의 `@Configuration`은 메인 컨텍스트가 아니라 **플러그인 자식 컨텍스트**에 등록됩니다.
- endpoint와 entrypoint connector 플러그인은 이 방식이 아닌 것으로 보입니다. Phase 1에서 `EndpointConnectorPluginHandler`로 확인할 질문입니다.

### 8. `@Conditional`

- `Condition` 구현의 `matches()`가 true일 때만 빈을 등록합니다.
- 예: `SyncConfiguration`의 `@Conditional(GammaEnabledCondition.class)`와 `@Conditional(GammaDisabledCondition.class)`는 설정에 따라 둘 중 하나의 빈만 만듭니다.
- 읽는 요령: "이 빈이 왜 안 만들어지지?" 싶으면 `@Conditional`이 붙어 있는지 확인하세요.

## 3. 공부하지 않아도 되는 것

| 주제 | 이유 |
|---|---|
| Spring Boot 전부 (auto-config, starter, actuator, `application.yml`) | 쓰지 않음 |
| `@Component` 스캔 방식 (`@ComponentScan`, `@Service`, `@Repository`) | Gateway는 거의 모두 `@Bean` 방식. `@Component`는 1곳 |
| Spring MVC, WebFlux, `@RestController` | HTTP는 Vert.x |
| Spring AOP, `@Transactional` | 사실상 쓰지 않음 (AOP 유틸 import 2곳) |
| Spring Data, JPA | DB 없음. repository는 Gravitee 자체 인터페이스 |
| Spring Security | 인증은 Gravitee 자체 security chain |
| Spring Events (`ApplicationEvent`) | Gravitee 자체 `EventManager`를 씀 |

## 4. 학습 순서 제안 (약 1~2일)

1. **Spring Framework 공식 문서 "Core Technologies"의 IoC Container 장**에서 다음 절만 읽습니다.
   - "Container Overview"
   - "Bean Overview"
   - "Dependencies"(DI)
   - "Bean Scopes"
   - "Java-based Container Configuration"(`@Configuration`, `@Bean`, `@Import`)
   - "Environment Abstraction"(`@Value`, property source)
2. **작은 실습 하나:** Spring Boot 없이 `AnnotationConfigApplicationContext`에 `@Configuration` 클래스 두 개를 `@Import`로 묶습니다. 같은 타입의 빈 두 개를 `@Qualifier`로 구분해 주입하고, `@Value`로 시스템 속성을 받아 봅니다. 이 실습 하나가 Gravitee 기동 구조의 축소판입니다.
3. **Gravitee 코드로 확인:** `StandaloneConfiguration`의 `@Import` 목록을 따라가며 "이 설정 클래스는 어떤 빈들을 만드는가"를 한 줄씩 적어 봅니다.
4. **디버거로 확인:** `suspend=y`로 띄워 `VertxReactorConfiguration.graviteeVerticle()`에 breakpoint를 걸고 Frames 창에서 호출 스택을 봅니다. `AbstractApplicationContext.refresh()`부터 `getBean()`까지 Spring이 빈을 만드는 과정이 보입니다.

## 5. 이해도 점검 질문

- [ ] `HttpRequestDispatcher` 빈은 어느 설정 클래스의 어느 메서드에서 만들어지는가?
- [ ] `@Qualifier("httpRequestDispatcher")`를 빼면 어떤 오류가 날 수 있고, 왜 그런가?
- [ ] `gravitee.yml`의 `http.port` 값이 `HttpProtocolVerticle`이 여는 서버 포트까지 전달되는 경로는?
- [ ] `HttpProtocolVerticle`을 singleton으로 바꾸면 어떤 문제가 생기는가?
- [ ] `services-sync` 플러그인의 빈이 메인 컨텍스트의 `ApiManager`를 주입받을 수 있는 이유는? 반대 방향은 왜 안 되는가?
- [ ] Phase 3에서 `handlers-guardian`을 지우려면 `StandaloneConfiguration`에서 무엇을 바꿔야 하는가?

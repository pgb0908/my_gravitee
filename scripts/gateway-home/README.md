# gateway-home

DB도 Management API도 없이 Gateway 하나만 띄우는 실행 환경(`GRAVITEE_HOME`)을 만들고 실행합니다. API 정의는 `apis/` 폴더의 JSON 파일에서 읽습니다.

원래 이 폴더는 `gravitee-apim-distribution` 모듈이 조립합니다. 하지만 distribution은 Maven Central에 없는 플러그인 zip 수십 개를 요구하고, 이 브랜치에서는 모듈 자체를 지웠습니다. 그래서 필요한 파일만 모아 최소 구성으로 만듭니다.

## 사용법

```bash
scripts/gateway-home/gateway-home.sh build     # Gateway에 필요한 모듈만 mvn install (테스트 생략)
scripts/gateway-home/gateway-home.sh assemble  # 빌드 결과물로 gateway-home 만들기/갱신
scripts/gateway-home/gateway-home.sh run       # Gateway 실행 (포그라운드, Ctrl+C로 종료)
scripts/gateway-home/gateway-home.sh all       # build → assemble → run
```

처음에는 `all`을 실행하세요. 그다음부터는 코드를 고칠 때마다 다음 순서로 실행합니다.

```bash
scripts/gateway-home/gateway-home.sh build && scripts/gateway-home/gateway-home.sh assemble
scripts/gateway-home/gateway-home.sh run
```

실행되면 확인해 봅니다. 기본 API는 `/echo`를 `http://localhost:8081`로 프록시합니다.

```bash
python3 -m http.server 8081 --bind 127.0.0.1   # 다른 터미널에서 테스트 백엔드 실행
curl -i http://localhost:8082/echo/             # Gateway를 거쳐 백엔드 응답이 오면 성공
```

## 환경 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `GATEWAY_HOME` | 저장소 옆 `../gateway-home` | 만들 폴더 위치 |
| `JAVA_HOME` | `~/.sdkman/candidates/java/25.0.4-tem` (있으면) | JDK 25 |
| `MVN` | PATH의 `mvn` | Maven 3.9 이상 |

## 사전 조건

- **JDK 25**, **Maven 3.9 이상**
- **`~/.m2`에 Gravitee upstream artifact가 설치되어 있어야 합니다.** `gravitee-common` 5.2.2, `gravitee-node` 9.17.0처럼 루트 pom이 요구하는 Gravitee 라이브러리 일부는 Maven Central에 없고 Gravitee의 비공개 피드에만 있습니다. 그래서 GitHub 공개 저장소의 고정 커밋을 직접 빌드해서 로컬에 설치해 두어야 합니다. 방법은 저장소 루트의 `fresh-clone-build-prompt.md`를 참고하세요. 루트 pom의 버전이 바뀌면 바뀐 라이브러리만 다시 빌드하면 됩니다.

## 각 명령이 하는 일

### `build`
standalone bootstrap과 container, 그리고 아래 플러그인 모듈과 그 의존 모듈(`-am`)만 `mvn install -DskipTests` 합니다. 라이선스와 prettier 검증은 그대로 실행됩니다.

### `assemble`
| 대상 | 처리 |
|---|---|
| `bin/gravitee` | 템플릿에서 매번 복사 (Gravitee 원본 실행 스크립트) |
| `config/gravitee.yml`, `config/logback.xml` | **없을 때만** 템플릿에서 복사. 직접 고친 설정은 유지됨 |
| `apis/` | **비어 있을 때만** `echo-api.json`을 복사. 직접 만든 API 정의는 유지됨 |
| `lib/` | 매번 비우고 다시 채움: bootstrap과 container jar, container의 런타임 의존성 |
| `plugins/` | 매번 비우고 다시 채움 (아래 표) |

| 플러그인 | 출처 | 왜 필요한가 |
|---|---|---|
| `entrypoint-http-proxy`, `endpoint-http-proxy` | 이 저장소 빌드 | V4 HTTP 프록시 |
| `repository-noop` | 이 저장소 빌드 | DB 없이 실행 (`type: none`) |
| `gateway-services-sync` | 이 저장소 빌드 | local sync가 이 플러그인 안에 있음 |
| `node-cluster-plugin-standalone`, `node-cache-plugin-standalone` | `~/.m2` (루트 pom의 `gravitee-node.version`) | 없으면 `NoClusterManagerException`으로 기동 실패 |
| `policy-keyless` 5.0.0 | Maven Central | Keyless 플랜이 정책 플러그인으로 구현되어 있음 |

jar나 zip이 없으면 `build`를 먼저 하라는 메시지를 내고 멈춥니다. IntelliJ에서 Maven `clean`이나 `compile`만 실행하면 `target/`에 jar와 zip이 없는 상태가 되니 주의하세요.

### `run`
`bin/gravitee`를 실행합니다. 이때 `-Dgravitee.gateway.log.dir=<home>/logs`를 넣어 로그를 `logs/gravitee.log`에 남깁니다. 원래 배포본에서는 패키징이 이 값을 넣어 주는데, 없으면 logback이 `gravitee.gateway.log.dir_IS_UNDEFINED` 폴더를 만듭니다.

## 만들어지는 폴더

```
gateway-home/
├── bin/gravitee          실행 스크립트
├── config/
│   ├── gravitee.yml      포트 8082, 저장소 type: none, local sync 켜기, 리포터·heartbeat·metrics 끄기
│   └── logback.xml
├── lib/                  classpath (jar 약 250개)
├── plugins/              플러그인 zip 7개
├── apis/                 local sync가 읽는 API 정의
└── logs/                 gravitee.log
```

## API 정의 파일 형식

local sync는 API 정의를 그대로 읽지 않습니다. Management API가 DB에 남기는 **배포 이벤트** 모양으로 감싼 파일을 읽습니다.

```json
{
  "apiEvent": {
    "id": "evt-echo-api",
    "type": "PUBLISH_API",
    "payload": "<repository Api 모델 JSON을 문자열로>",
    "properties": { "api_id": "echo-api", "deployment_number": "1" }
  }
}
```

- `payload`는 `io.gravitee.repository.management.model.Api`를 **JSON 문자열로** 넣은 것입니다. 그 안의 `definition`도 V4 API 정의(`io.gravitee.definition.model.v4.Api`)를 다시 **문자열로** 넣습니다. 즉 이중으로 감싸여 있습니다.
- `payload`의 `definitionVersion`은 `"V4"`가 아니라 **`"4.0.0"`** 으로 써야 합니다. 다르게 쓰면 V2로 해석되어 배포에 실패합니다.
- `lifecycleState`가 `"STARTED"`여야 요청을 받습니다.
- 플랜의 보안 타입(`key-less`, `api-key`, `jwt` 등)마다 해당 **정책 플러그인 zip**이 `plugins/`에 있어야 합니다.
- 파일을 추가하거나 고치거나 지우면 **재시작 없이** 바로 배포, 재배포, 해제됩니다.

파일 하나를 직접 만드는 대신 `template/apis/echo-api.json`을 복사해서 고치는 게 편합니다.

## 주의할 점

- local sync는 코드 주석에 *"INTERNAL USE ONLY ... not production ready"* 라고 적혀 있는 테스트용 모드입니다. 분석과 로컬 실험용으로만 쓰세요.
- 실행 로그의 Kubernetes 설정 ERROR(k8s 환경이 아니라서), EL whitelist WARN, health probe 바인딩 ERROR는 기동과 프록시 동작에 영향이 없습니다.
- 플러그인은 기동할 때만 읽습니다. `plugins/`를 바꾸면 Gateway를 재시작해야 합니다.

## 파일 구성

```
scripts/gateway-home/
├── gateway-home.sh
├── README.md
└── template/
    ├── bin/gravitee            master의 gravitee-apim-distribution-standalone-gateway에서 복사 (수정 없음)
    ├── config/logback.xml      위와 같음 (라이선스 헤더만 이 저장소 형식으로 바꿈)
    ├── config/gravitee.yml     최소 구성용으로 새로 작성
    └── apis/echo-api.json      테스트용 V4 프록시 API
```

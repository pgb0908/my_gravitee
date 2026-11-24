#!/usr/bin/env bash
#
# Copyright © 2015 The Gravitee team (http://gravitee.io)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Builds and runs a minimal standalone Gateway home: no database, no Management API,
# APIs read from <home>/apis by the local sync.
#
# Usage: gateway-home.sh <command>
#   build     mvn install of the modules the Gateway needs (tests skipped)
#   assemble  (re)create the home from the build output and the pinned external plugins
#   run       start the Gateway in the foreground
#   all       build + assemble + run
#
# Environment:
#   GATEWAY_HOME  target directory (default: <repo>/../gateway-home)
#   JAVA_HOME     JDK 25 (default: the SDKMAN 25 install if present)
#   MVN           Maven 3.9+ binary (default: mvn on PATH)

set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
template="$script_dir/template"
home=${GATEWAY_HOME:-"$(dirname "$repo")/gateway-home"}
mvn=${MVN:-mvn}

if [[ -z "${JAVA_HOME:-}" && -d "$HOME/.sdkman/candidates/java/25.0.4-tem" ]]; then
    export JAVA_HOME="$HOME/.sdkman/candidates/java/25.0.4-tem"
fi
[[ -n "${JAVA_HOME:-}" ]] && export PATH="$JAVA_HOME/bin:$PATH"

# External plugins that are not built by this repository. The node plugins follow the
# gravitee-node version the root POM pins; the keyless policy is the release on Maven Central.
keyless_policy_version=5.0.0

gw=gravitee-apim-gateway
standalone=$gw/gravitee-apim-gateway-standalone
repo_plugins=(
    gravitee-apim-repository/gravitee-apim-repository-noop
    gravitee-apim-plugin/gravitee-apim-plugin-entrypoint/gravitee-apim-plugin-entrypoint-http-proxy
    gravitee-apim-plugin/gravitee-apim-plugin-endpoint/gravitee-apim-plugin-endpoint-http-proxy
    $gw/gravitee-apim-gateway-services/gravitee-apim-gateway-services-sync
)

maven() {
    (cd "$repo" && "$mvn" -B -ntp "$@")
}

project_version() {
    # stderr only carries the JDK's sun.misc.Unsafe warnings about Maven's own Guice.
    maven -q -N help:evaluate "-Dexpression=$1" -DforceStdout 2>/dev/null
}

build() {
    local modules
    modules=$(IFS=,; echo "$standalone/gravitee-apim-gateway-standalone-bootstrap,$standalone/gravitee-apim-gateway-standalone-container,${repo_plugins[*]}")
    maven install -DskipTests -pl "$modules" -am
}

copy_artifact() {
    maven -q dependency:copy "-Dartifact=$1" "-DoutputDirectory=$2"
}

assemble() {
    local version node_version module
    version=$(project_version project.version)
    node_version=$(project_version gravitee-node.version)

    mkdir -p "$home"/{bin,config,apis,lib,plugins,logs,license,metrics,models}

    cp "$template/bin/gravitee" "$home/bin/gravitee"
    chmod +x "$home/bin/gravitee"
    # Keep local edits to the configuration and the API definitions; only seed what is missing.
    for file in config/gravitee.yml config/logback.xml; do
        [[ -f "$home/$file" ]] || cp "$template/$file" "$home/$file"
    done
    if [[ -z "$(ls -A "$home/apis")" ]]; then
        cp "$template"/apis/*.json "$home/apis/"
    fi

    rm -f "$home"/lib/*.jar
    for module in bootstrap container; do
        local jar="$repo/$standalone/gravitee-apim-gateway-standalone-$module/target/gravitee-apim-gateway-standalone-$module-$version.jar"
        [[ -f "$jar" ]] || { echo "Missing $jar: run '$0 build' first." >&2; exit 1; }
        cp "$jar" "$home/lib/"
    done
    maven -q -pl "$standalone/gravitee-apim-gateway-standalone-container" \
        dependency:copy-dependencies -DincludeScope=runtime "-DoutputDirectory=$home/lib"

    rm -f "$home"/plugins/*.zip
    for module in "${repo_plugins[@]}"; do
        local zip="$repo/$module/target/$(basename "$module")-$version.zip"
        [[ -f "$zip" ]] || { echo "Missing $zip: run '$0 build' first." >&2; exit 1; }
        cp "$zip" "$home/plugins/"
    done
    copy_artifact "io.gravitee.node:gravitee-node-cluster-plugin-standalone:$node_version:zip" "$home/plugins"
    copy_artifact "io.gravitee.node:gravitee-node-cache-plugin-standalone:$node_version:zip" "$home/plugins"
    copy_artifact "io.gravitee.policy:gravitee-policy-keyless:$keyless_policy_version:zip" "$home/plugins"

    echo "Gateway home ready: $home ($(ls "$home/lib" | wc -l) jars, $(ls "$home/plugins" | wc -l) plugins)"
}

run() {
    [[ -x "$home/bin/gravitee" ]] || { echo "No Gateway home at $home: run '$0 assemble' first." >&2; exit 1; }
    # logback.xml writes to ${gravitee.gateway.log.dir}, which the distribution's packaging normally sets.
    export JAVA_OPTS="${JAVA_OPTS:-} -Dgravitee.gateway.log.dir=$home/logs"
    exec "$home/bin/gravitee"
}

case "${1:-}" in
    build) build ;;
    assemble) assemble ;;
    run) run ;;
    all) build && assemble && run ;;
    *)
        sed -n '/^# Usage:/,/^#   MVN/p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac

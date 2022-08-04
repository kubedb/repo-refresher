#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=dbc22 # -$(date +%s)
COMMIT_MSG="Update db-client-go"

REPO_ROOT=/tmp/kubedb-repo-refresher

KUBEDB_API_REF=${KUBEDB_API_REF:-1241b40d48ec513379b1b2aabd80215e9b93b319}

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 https://${GITHUB_USER}:${GITHUB_TOKEN}@$1.git
    name=$(ls -b1)
    cd $name
    git checkout -b $PR_BRANCH
    if [ -f go.mod ]; then
        cat <<EOF > go.mod
module kubedb.dev/$name

go 1.18

EOF
        # https://stackoverflow.com/a/63918676/244009
        # sed -i '' -e 's|github.com/jetstack/cert-manager|github.com/cert-manager/cert-manager|g' `grep 'jetstack' -rl *`
        sed -i 's|github.com/jetstack/cert-manager|github.com/cert-manager/cert-manager|g' `grep 'jetstack' -rl *`

        # sed -i "s|go 1.12|go 1.17|g" go.mod
        # sed -i "s|go 1.13|go 1.17|g" go.mod
        # sed -i "s|go 1.14|go 1.17|g" go.mod
        # sed -i "s|go 1.15|go 1.17|g" go.mod
        # sed -i "s|go 1.16|go 1.17|g" go.mod
        # if [ "$1" != "github.com/kubedb/apimachinery" ]; then
        #     go mod edit \
        #         -require kubedb.dev/apimachinery@${KUBEDB_API_REF}
        #     go mod tidy
        # fi
        go mod edit \
            -require=kubedb.dev/apimachinery@${KUBEDB_API_REF} \
            -require=kubedb.dev/db-client-go@v0.0.2 \
            -require=k8s.io/kube-openapi@v0.0.0-20220328201542-3ee0da9b0b42 \
            -require=kmodules.xyz/resource-metadata@v0.12.5 \
            -replace=github.com/Masterminds/sprig/v3=github.com/gomodules/sprig/v3@v3.2.3-0.20220405051441-0a8a99bac1b8 \
            -require=gomodules.xyz/password-generator@v0.2.8 \
            -require=go.bytebuilders.dev/license-verifier@v0.11.0 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.11.0 \
            -require=go.bytebuilders.dev/audit@v0.0.23 \
            -require=stash.appscode.dev/apimachinery@v0.22.0 \
            -require=go.mongodb.org/mongo-driver@v1.9.1 \
            -replace=sigs.k8s.io/controller-runtime=github.com/kmodules/controller-runtime@v0.12.2-0.20220603144237-6cd001896bf3 \
            -replace=github.com/imdario/mergo=github.com/imdario/mergo@v0.3.5 \
            -replace=k8s.io/apimachinery=github.com/kmodules/apimachinery@v0.24.2-rc.0.0.20220603191800-1c7484099dee \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.0.0-20220603223637-59dad1716c43 \
            -replace=k8s.io/kubernetes=github.com/kmodules/kubernetes@v1.25.0-alpha.0.0.20220603172133-1c9d09d1b3b8

        cat <<EOF >> go.mod
replace (
    go.opentelemetry.io/contrib => go.opentelemetry.io/contrib v0.20.0
    go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc => go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.20.0
    go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp => go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.20.0
    go.opentelemetry.io/otel => go.opentelemetry.io/otel v0.20.0
    go.opentelemetry.io/otel/exporters/otlp => go.opentelemetry.io/otel/exporters/otlp v0.20.0
    go.opentelemetry.io/otel/metric => go.opentelemetry.io/otel/metric v0.20.0
    go.opentelemetry.io/otel/oteltest => go.opentelemetry.io/otel/oteltest v0.20.0
    go.opentelemetry.io/otel/sdk => go.opentelemetry.io/otel/sdk v0.20.0
    go.opentelemetry.io/otel/sdk/export/metric => go.opentelemetry.io/otel/sdk/export/metric v0.20.0
    go.opentelemetry.io/otel/sdk/metric => go.opentelemetry.io/otel/sdk/metric v0.20.0
    go.opentelemetry.io/otel/trace => go.opentelemetry.io/otel/trace v0.20.0
    go.opentelemetry.io/proto/otlp => go.opentelemetry.io/proto/otlp v0.7.0
)
EOF

        go mod tidy
        go mod vendor
    fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # run an extra make fmt because when make gen fails, make fmt is not run
        make fmt || true
    )
    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin $PR_BRANCH -f
        hub pull-request \
            --labels automerge \
            --message "$COMMIT_MSG" \
            --message "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" || true
        # gh pr create \
        #     --base master \
        #     --fill \
        #     --label automerge \
        #     --reviewer tamalsaha
    fi
    popd
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Correct usage: $SCRIPT_NAME <path_to_repos_list>"
    exit 1
fi

if [ -x $GITHUB_TOKEN ]; then
    echo "Missing env variable GITHUB_TOKEN"
    exit 1
fi

# ref: https://linuxize.com/post/how-to-read-a-file-line-by-line-in-bash/#using-file-descriptor
while IFS=, read -r -u9 repo cmd; do
    if [ -z "$repo" ]; then
        continue
    fi
    refresh "$repo" "$cmd"
    echo "################################################################################"
done 9<$1

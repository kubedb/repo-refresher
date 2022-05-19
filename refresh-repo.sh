#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=kubedb-repo-refresher # -$(date +%s)
COMMIT_MSG="Update dependencies"

REPO_ROOT=/tmp/kubedb-repo-refresher

KUBEDB_API_REF=${KUBEDB_API_REF:-3634eb14c9acb5ab68071fa38ca0b5236e266094}

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
    cd $(ls -b1)
    git checkout -b $PR_BRANCH
    if [ -f go.mod ]; then
        sed -i "s|go 1.12|go 1.17|g" go.mod
        sed -i "s|go 1.13|go 1.17|g" go.mod
        sed -i "s|go 1.14|go 1.17|g" go.mod
        sed -i "s|go 1.15|go 1.17|g" go.mod
        sed -i "s|go 1.16|go 1.17|g" go.mod
        if [ "$1" != "github.com/kubedb/apimachinery" ]; then
            go mod edit \
                -require kubedb.dev/apimachinery@${KUBEDB_API_REF}
            go mod tidy
        fi
        go mod edit \
            -require=kmodules.xyz/client-go@dc247aa7f6df368645b0b5b28c37c1c2e6b11f6d \
            -require=kmodules.xyz/monitoring-agent-api@5a48a0a1d3f8e8e51a03704ddae1758113f74ad7 \
            -require=kmodules.xyz/webhook-runtime@0ddfc9e4c2214ebcc4acd9e33d2f8e9880de1428 \
            -require=kmodules.xyz/resource-metadata@v0.10.16 \
            -require=kmodules.xyz/custom-resources@237eae1d7ddd7dd2b5384b5f306aa489ef6c49ef \
            -require=kmodules.xyz/objectstore-api@f1d593d0a778b3f502dfff9cdcb759ac5e55e6a4 \
            -require=kmodules.xyz/offshoot-api@fefb02c26514eb8cb52b88697d0e6104f2241caf \
            -require=go.bytebuilders.dev/license-verifier@v0.9.7 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.9.7 \
            -require=go.bytebuilders.dev/audit@v0.0.20 \
            -require=gomodules.xyz/x@v0.0.14 \
            -require=gomodules.xyz/logs@v0.0.6 \
            -require=stash.appscode.dev/apimachinery@v0.20.1 \
            -require=kubedb.dev/db-client-go@9c63e21a217832cf5f84a5426360570e58870d70 \
            -require=go.mongodb.org/mongo-driver@v1.9.1 \
            -replace=github.com/satori/go.uuid=github.com/gomodules/uuid@v4.0.0+incompatible \
            -replace=github.com/dgrijalva/jwt-go=github.com/gomodules/jwt@v3.2.2+incompatible \
            -replace=github.com/golang-jwt/jwt=github.com/golang-jwt/jwt@v3.2.2+incompatible \
            -replace=github.com/form3tech-oss/jwt-go=github.com/form3tech-oss/jwt-go@v3.2.5+incompatible \
            -replace=helm.sh/helm/v3=github.com/kubepack/helm/v3@v3.6.1-0.20210518225915-c3e0ce48dd1b \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.21.2-0.20220112070009-e3f6e88991d9
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

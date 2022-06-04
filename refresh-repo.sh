#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=k124 # -$(date +%s)
COMMIT_MSG="Update to k8s 1.24 toolchain"

REPO_ROOT=/tmp/kubedb-repo-refresher

KUBEDB_API_REF=${KUBEDB_API_REF:-666ce9c7cf9f2d5665e299d2d133662a691ea2ed}

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
        # sed -i "s|go 1.12|go 1.17|g" go.mod
        # sed -i "s|go 1.13|go 1.17|g" go.mod
        # sed -i "s|go 1.14|go 1.17|g" go.mod
        # sed -i "s|go 1.15|go 1.17|g" go.mod
        # sed -i "s|go 1.16|go 1.17|g" go.mod
        if [ "$1" != "github.com/kubedb/apimachinery" ]; then
            go mod edit \
                -require kubedb.dev/apimachinery@${KUBEDB_API_REF}
            go mod tidy
        fi
        go mod edit \
            -require=k8s.io/kube-openapi@v0.0.0-20220328201542-3ee0da9b0b42 \
            -require=kmodules.xyz/resource-metadata@v0.11.0 \
            -require=go.bytebuilders.dev/license-verifier@v0.10.0 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.10.0 \
            -require=go.bytebuilders.dev/audit@v0.0.22 \
            -require=stash.appscode.dev/apimachinery@b90c85f4fd8ce0095885ad6c1da26557fbf87182 \
            -require=kubedb.dev/db-client-go@9c63e21a217832cf5f84a5426360570e58870d70 \
            -require=go.mongodb.org/mongo-driver@v1.9.1 \
            -replace=github.com/imdario/mergo=github.com/imdario/mergo@v0.3.5 \
            -replace=k8s.io/apimachinery=github.com/kmodules/apimachinery@v0.24.2-rc.0.0.20220603191800-1c7484099dee \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.0.0-20220603223637-59dad1716c43 \
            -replace=k8s.io/kubernetes=github.com/kmodules/kubernetes@v1.25.0-alpha.0.0.20220603172133-1c9d09d1b3b8
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

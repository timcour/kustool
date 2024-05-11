#!/usr/bin/env bats

# Must have KUSTOOL_ROOT in env
EASY_PATCH="${KUSTOOL_ROOT}/kustool-easy-patch.sh"

function pass {
    echo ""
}

@test "happy path" {
    result=$($EASY_PATCH --kind Deployment --name nginx-deployment \
                         --file-to-diff ${KUSTOOL_ROOT}/test/data/easy-patch-happy-path-edited.yaml \
                         test/cluster-a/web/kustomization.yaml | yq)

    expected_path="${KUSTOOL_ROOT}/test/data/easy-patch-happy-path-expected.yaml"

    diff  "$expected_path" <(echo "${result}")
    [ "$?" ]
}

@test "adds target kind/name when adding a new patch" {
    skip "not yet supported"

    result=$($EASY_PATCH --kind Deployment --name nginx-deployment \
                         --debug --file-to-diff ${KUSTOOL_ROOT}/test/data/easy-patch-new-target-edited.yaml \
                         test/cluster-a/web/nginx/kustomization.yaml | yq)

    expected_path="${KUSTOOL_ROOT}/test/data/easy-patch-new-target-expected.yaml"

    diff  "$expected_path" <(echo "${result}")
    [ "$?" ]
}

@test "--help should exit 0" {
    $EASY_PATCH --help
    [ "$?" ]
}

@test "kustomize build should be identical to the edited original" {
    skip "not yet tested"
}

@test "the -w option should update the specified kustomization.yaml" {
    skip "not yet tested"
}

@test "the --debug option should print a bunch of messages to stderr" {
    skip "not yet tested"
}

@test "should always print the final (and only the final) kustomize.yaml to stdout" {
    skip "not yet tested"
}

#!/usr/bin/env bats

# Must have KUSTOOL_ROOT in env
EASY_PATCH="${KUSTOOL_ROOT}/kustool-easy-patch.sh"

@test "happy path" {

    expected=$(echo "apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: web
resources:
  - nginx
patches:
  - target:
      name: nginx-deployment
      kind: Deployment
    patch: |-
      - op: add
        path: /foo
        value: bar" | yq)


    result=$($EASY_PATCH --kind Deployment --name nginx-deployment --file-to-diff ${KUSTOOL_ROOT}/test/data/easy-patch-happy-path-edited.yaml test/cluster-a/web/kustomization.yaml | yq)

    diff <(echo "${result}") <(echo "${expected}")

    [ "$result" == "$expected" ]
}

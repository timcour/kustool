# Kustomization Utilities

[Kustomization GitHub](https://github.com/kubernetes-sigs/kustomize)

## `kustool-easy-patch.sh` - Patch using interactive editor
Generates yaml patches to be used in a `kustomization.yaml`.

``` shell
 $ ./kustool-easy-patch.sh --help
Usage: ./kustool-easy-patch.sh <kustomization-path> [flags...]

  kustomization-path - /path/to/kustomization.yaml

Flags:
  -k --kind      - Kubernetes resource .kind
  -n --name      - Kubernetes resource .metadata.name
  -w --write     - Write updated patch target to specified
                   kustomization.yaml
  --file-to-diff - bypass the interactive editor, use an already
                   edited file.  Useful for testing.
  --debug        - print debug messages
  -h --help      - print this message and exit

Example:
  Auto-update (or add) a patch to Deployment named 'app-name'
    ./kustool-easy-patch.sh --kind Deployment --name app-name /path/to/kustomization.yaml
```

# Kustomization Utilities

[Kustomization GitHub](https://github.com/kubernetes-sigs/kustomize)

## `kustool-easy-patch.sh` - Interactive Kustomize patching
Using your bash $EDITOR, edit the kustomize-built artifact directly to
add or update your `.patches` in a `kustomization.yaml`.

```
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

## Development
### Dependencies

- [jd](https://github.com/josephburnett/jd) - JSON Diff
- [yq](https://github.com/mikefarah/yq) - YAML Parsing
- [bats-core](https://github.com/bats-core/bats-core) - Unit tests

With homebrew:

``` shell
brew bundle
```

### Running Tests

``` shell
make test
```

#!/bin/bash

# TODO: Validation checks
# - check for valid kustomization file
# - check for valid kustomize build

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

POSITIONAL_ARGS=()

function help {
    ERROR="$1"
    if [ ! -z "${ERROR}" ]; then
        echo "Error: $1"
    fi
    echo "Usage: $0 <kustomization-path> [flags...]"
    echo ""
    echo "  kustomization-path - /path/to/kustomization.yaml"
    echo ""
    echo "Flags:"
    echo "  -k --kind      - Kubernetes resource .kind"
    echo "  -n --name      - Kubernetes resource .metadata.name"
    echo "  -w --write     - Write updated patch target to specified"
    echo "                   kustomization.yaml"
    echo "  --file-to-diff - bypass the interactive editor, use an already"
    echo "                   edited file.  Useful for testing."
    echo "  --debug        - print debug messages"
    echo "  -h --help      - print this message and exit"
    echo ""
    echo "Example:"
    echo "  Auto-update (or add) a patch to Deployment named 'app-name'"
    echo "    $0 --kind Deployment --name app-name /path/to/kustomization.yaml"
}

function debug {
    if [ -z "${DEBUG}" ]; then
        return
    fi

    >&2 echo -e "DEBUG: $@"
}

RESOURCE_PARTS=""
PATCHES_PARTS=""
NONTARGET_PARTS=""
TARGET_YAML="target: {}"
while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--kind)
      export KIND=$2
      RESOURCE_PARTS="$RESOURCE_PARTS .kind==\"${KIND}\""
      PATCHES_PARTS="$PATCHES_PARTS .target.kind==\"${KIND}\""
      NONTARGET_PARTS="$NONTARGET_PARTS .target.kind!=\"${KIND}\""
      shift
      shift
      ;;
    -n|--name)
      NAME=$2
      RESOURCE_PARTS="$RESOURCE_PARTS .metadata.name==\"${NAME}\""
      PATCHES_PARTS="$PATCHES_PARTS .target.name==\"${NAME}\""
      NONTARGET_PARTS="$NONTARGET_PARTS .target.name!=\"${NAME}\""
      shift
      shift
      ;;
    -w|--write)
      WRITE_KUSTOMIZATION_UPDATE=1
      shift
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    -h|--help)
      HELP="$2"
      help
      exit 0
      ;;
    --file-to-diff)
      FILE_TO_DIFF="$2"
      shift;
      shift;
      ;;
    -*|--*)
      help "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

#TODO: Associative arrays would be cleaner, but punting because issues
export RESOURCE_SELECT=$(join_by ' and ' $RESOURCE_PARTS)
export PATCHES_SELECT=$(join_by ' and ' $PATCHES_PARTS)
export NOMUTATE_SELECT=$(join_by ' and ' $NONTARGET_PARTS)

debug "RESOURCE_SELECT:\n    ${RESOURCE_SELECT}"
debug "PATCHES_SELECT:\n    ${PATCHES_SELECT}"
debug "NOMUTATE_SELECT:\n    ${NOMUTATE_SELECT}"

KUST_FILE=$1

function mktemp_yaml {
    filename=$1
    dir=$(mktemp -d)
    path="$dir"/"$filename"
    touch "$path"
    echo "$path"
}

KUST_DIR=$(dirname "${KUST_FILE}")
EDIT_FILE=$(mktemp_yaml "exit_file.yaml")
UNPATCHED_BUILD_FILE=$(mktemp_yaml "unpatched_build_file.yaml")
debug "UNPATCHED_BUILD_FILE: $UNPATCHED_BUILD_FILE"
debug "EDIT_FILE: $EDIT_FILE"

function rm_whitespace {
    sed 's/ *$//'
}

function build {
    DIR_PATH=$1

    kustomize build --load-restrictor LoadRestrictionsNone ${DIR_PATH}
}

function delete_patches {
    yq 'del(.patches)'
}

function push_unpatched_kustomize {
    BAKFILE=${1:-"${KUST_FILE}.bak"}

    mv "${KUST_FILE}" "${BAKFILE}"
    debug "writing unpatched kustomization"
    debug $(cat "${BAKFILE}" | delete_patches)
    cat "${BAKFILE}" | delete_patches > "${KUST_DIR}"/kustomization.yaml
}

function pop_unpatched_kustomize {
    BAKFILE=${1:-"${KUST_FILE}.bak"}

    mv  "${BAKFILE}" "${KUST_FILE}"
}

function replace_patch_target {
    export SELECT="${1}"
    export PATCH_TARGET="${2}"

    yq '.patches |= filter(eval(strenv(SELECT))) *+ env(PATCH_TARGET)'
}

function write_edit_file {
    kust_file="${1}"
    selector="${2}"
    edit_file="${3}"

    "${SCRIPT_DIR}"/kustool-filter-resource.sh "${kust_file}" -s "${selector}" > ${edit_file}
}

function write_unpatched_kustomize_file {
    kust_file="${1}"
    selector="${2}"
    unpatched_kust_file="${3}"

    push_unpatched_kustomize "${kust_file}.bak"
    "${SCRIPT_DIR}"/kustool-filter-resource.sh "${kust_file}" -s "${selector}" > ${unpatched_kust_file}
    pop_unpatched_kustomize "${kust_file}.bak"
}

function target_from_resource {
    FILE="${1}"
    kind=$(yq '.kind' "${FILE}")
    name=$(yq '.metadata.name' "${FILE}")

    debug "kind: $kind; name: $name"
    echo "target: {\"kind\":\"${kind}\",\"name\":\"${name}\"}"
}

### Validation
if [ -z ${KUST_FILE} ]; then
    help "Path to kustomization.yaml not specified"
    exit 1
fi

debug "Filtering kustomize build resources: ${KUST_FILE}; select: ${RESOURCE_SELECT}"
# only one document at a time supported
RESOURCE_COUNT=$("${SCRIPT_DIR}"/kustool-filter-resource.sh -c "${KUST_FILE}" -s "${RESOURCE_SELECT}")
if [ "$?" -ne 0 ]; then
    debug "RESOURCE_COUNT failed: ${RESOURCE_COUNT}"
    exit 1
fi

if [[ ${RESOURCE_COUNT} -gt 1 ]]; then
    echo "Only one supported at this time.  Ensure --kind and --name are"
    echo " specified."
    help "Matching resource count: $RESOURCE_COUNT."
    exit 1
fi
#TODO: also ensure _at most_ one patch matches

# Build and write current fully _patched_ yaml to EDIT_FILE
write_edit_file "${KUST_FILE}" "${RESOURCE_SELECT}" ${EDIT_FILE}
export BASE_TARGET=$(target_from_resource ${EDIT_FILE})
write_unpatched_kustomize_file "${KUST_FILE}" "${RESOURCE_SELECT}" "${UNPATCHED_BUILD_FILE}"

# edit EDIT_FILE
# TODO: why does quoting the tempfile not work?
if [ ! -z $FILE_TO_DIFF ]; then
    cat "${FILE_TO_DIFF}" > ${EDIT_FILE}
else
    "${EDITOR:-vi}" ${EDIT_FILE}
fi

if ! cat ${EDIT_FILE} | yq > /dev/null; then
    echo "Error parsing yaml:"
    cat -n ${EDIT_FILE}
    echo ""
    cat ${EDIT_FILE} | yq
    exit 1
fi

# get the diff with jd
export PATCHES="$(jd -f patch -yaml ${UNPATCHED_BUILD_FILE} ${EDIT_FILE} | yq -P -o yaml)"

debug "Generated updated yamlfied JSON patch"
debug "${PATCHES}"

debug "Filter select query for other patch targets: $NOMUTATE_SELECT"

# Grab the .target to update from the specified kustomize.yaml, then
# set its .patch to the updated patch string.
CURRENT_PATCHES_TARGET=$(cat "${KUST_FILE}" | yq '.patches | filter(eval(strenv(PATCHES_SELECT))) | .[0] *+ env(BASE_TARGET) | [.]' | yq -P)
debug "CURRENT_PATCHES_TARGET\n${CURRENT_PATCHES_TARGET}"

export NEW_PATCH_TARGET=$(echo "${CURRENT_PATCHES_TARGET}" | yq  '.[0].patch |= strenv(PATCHES)')
debug "The patched patch target"
debug "${NEW_PATCH_TARGET}"

debug "Generating kustomization with updated patch target"
debug "  would write to ${KUST_FILE}"
NEW_KUSTOMIZATION=$(cat "${KUST_FILE}" | replace_patch_target "${NOMUTATE_SELECT}" "${NEW_PATCH_TARGET}")
echo "${NEW_KUSTOMIZATION}"

# Write to kustomization.yaml if flag is set
if [ ! -z ${WRITE_KUSTOMIZATION_UPDATE} ]; then
    echo "${NEW_KUSTOMIZATION}" > "${KUST_FILE}"
    debug "Updated ${KUST_FILE}"
fi

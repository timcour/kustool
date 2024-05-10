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

while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--kind)
      KIND=$2
      shift
      shift
      ;;
    -n|--name)
      NAME=$2
      shift
      shift
      ;;
    -w|--write)
      WRITE_KUSTOMIZATION_UPDATE=1
      shift
      shift
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    -h|--HELP)
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

KUST_FILE=$1

KUST_DIR=$(dirname "${KUST_FILE}")
EDIT_FILE=$(mktemp)
UNPATCHED_BUILD_FILE=$(mktemp)

if [ -z ${KUST_FILE} ]; then
    help "Path to kustomization.yaml not specified"
    exit 1
fi

function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

QUERY_PARTS=""
if [[ ! -z "${KIND}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .kind==\"${KIND}\""
fi
if [[ ! -z "${NAME}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .metadata.name==\"${NAME}\""
fi
RESOURCE_SELECT=$(join_by ' and ' $QUERY_PARTS)
debug "RESOURCE_SELECT yq selection query"
debug "${RESOURCE_SELECT}"

QUERY_PARTS=""
if [[ ! -z "${KIND}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .target.kind==\"${KIND}\""
fi
if [[ ! -z "${NAME}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .target.name==\"${NAME}\""
fi
# yq '.patches[] | select(.target.kind== "Deployment")'
export PATCHES_SELECT=$(join_by ' and ' $QUERY_PARTS)

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

debug "Filtering kustomize build resources: ${KUST_FILE}; select: ${RESOURCE_SELECT}"
# only one document at a time supported
RESOURCE_COUNT=$("${SCRIPT_DIR}"/kustool-filter-resource.sh -c "${KUST_FILE}" -s "${RESOURCE_SELECT}")
if [[ ${RESOURCE_COUNT} -gt 1 ]]; then
    echo "Only one supported at this time.  Ensure --kind and --name are"
    echo " specified."
    help "Matching resource count: $RESOURCE_COUNT."
    exit 1
fi
#TODO: also ensure _at most_ one patch matches

# Build and write current fully _patched_ yaml to EDIT_FILE
"${SCRIPT_DIR}"/kustool-filter-resource.sh "${KUST_FILE}" -s "${RESOURCE_SELECT}" > ${EDIT_FILE}

# Remove patches, build and write _unpatched_ yaml to UNPATCHED_BUILD_FILE
push_unpatched_kustomize "${KUST_FILE}.bak"
"${SCRIPT_DIR}"/kustool-filter-resource.sh "${KUST_FILE}" -s "${RESOURCE_SELECT}" > ${UNPATCHED_BUILD_FILE}
pop_unpatched_kustomize "${KUST_FILE}.bak"

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

#TODO: only echo of -p specified
debug "Generated updated yamlfied JSON patch"
debug "${PATCHES}"

#TODO: insert (or replace) the single patch matching PATCHES_SELECT _using_ the .kind/.metadata.name from the yaml resource.

# Filter out target element
#yq '.patches | filter(.target.kind != "Deployment" or .target.name != "external-dns-whisman-fulfil-ai")

QUERY_PARTS=""
if [[ ! -z "${KIND}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .target.kind!=\"${KIND}\""
fi
if [[ ! -z "${NAME}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .target.name!=\"${NAME}\""
fi
# yq '.patches[] | select(.target.kind== "Deployment")'
export NOMUTATE_SELECT="$(join_by ' or ' $QUERY_PARTS)"

debug "Filter select query for other patch targets: $NOMUTATE_SELECT"


CURRENT_PATCH_TARGET=$(cat "${KUST_FILE}" | yq  '.patches | filter(eval(strenv(PATCHES_SELECT)))')
debug "CURRENT_PATCH_TARGET\n"${CURRENT_PATCH_TARGET}""

export NEW_PATCH_TARGET=$(echo "${CURRENT_PATCH_TARGET}" | yq  '.[0].patch |= strenv(PATCHES)')
debug "The patched patch target"
debug "${NEW_PATCH_TARGET}"

function replace_patch_target {
    export SELECT="${1}"
    export PATCH_TARGET="${2}"
    yq '.patches |= filter(eval(strenv(SELECT))) *+ env(PATCH_TARGET)'
}

# # Remove the single patch target from the original, and append the new
# debug "without function"
# cat "${KUST_FILE}" | yq '.patches |= filter(eval(strenv(NOMUTATE_SELECT))) *+ env(NEW_PATCH_TARGET)'

debug "Generating kustomization with updated patch target"
NEW_KUSTOMIZATION=$(cat "${KUST_FILE}" | replace_patch_target "${NOMUTATE_SELECT}" "${NEW_PATCH_TARGET}")
echo "${NEW_KUSTOMIZATION}"

if [ ! -z ${WRITE_KUSTOMIZATION_UPDATE} ]; then
    echo "${NEW_KUSTOMIZATION}" > ${KUST_FILE}
    debug "Updated ${KUST_FILE}"
fi

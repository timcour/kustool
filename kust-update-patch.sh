#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

POSITIONAL_ARGS=()

function help {
    ERROR="$1"
    if [ ! -z "${ERROR}" ]; then
        echo "Error: $1"
    fi
    echo "Usage: $0 KUSTOMIZATION_PATH"
    echo ""
    echo "  KUSTOMIZATION_PATH - /path/to/kustomization.yaml"
    echo "  -k --kind - Kubernetes resource .kind"
    echo "  -n --name - Kubernetes resource .metadata.name"
    echo "  -h --help - print this message and exit"
    echo ""
    echo "Example:"
    echo "  Auto-update (or add) a patch to Deployment named 'app-name'"
    echo "    $0 --kind Deployment --name app-name /path/to/kustomization.yaml"
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
    -h|--HELP)
      HELP="$2"
      help
      exit 0
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

QUERY_PARTS=""
if [[ ! -z "${KIND}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .target.kind==\"${KIND}\""
fi
if [[ ! -z "${NAME}" ]]; then
    QUERY_PARTS="$QUERY_PARTS .target.name==\"${NAME}\""
fi
# yq '.patches[] | select(.target.kind== "Deployment")'
PATCHES_SELECT=$(join_by ' and ' $QUERY_PARTS)


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
    echo "writing unpatched kustomization"
    cat "${BAKFILE}" | delete_patches
    cat "${BAKFILE}" | delete_patches > "${KUST_DIR}"/kustomization.yaml
}

function pop_unpatched_kustomize {
    BAKFILE=${1:-"${KUST_FILE}.bak"}
    mv  "${BAKFILE}" "${KUST_FILE}"
}

# only one document at a time supported
RESOURCE_COUNT=$("${SCRIPT_DIR}"/kustomize-select-resource.sh -c "${KUST_FILE}" -s "${RESOURCE_SELECT}")
if [[ ${RESOURCE_COUNT} -gt 1 ]]; then
    echo "Only one supported at this time.  Ensure --kind and --name are"
    echo " specified."
    help "Matching resource count: $RESOURCE_COUNT."
    exit 1
fi
#TODO: also ensure _at most_ one patch matches

# Build and write current fully _patched_ yaml to EDIT_FILE
"${SCRIPT_DIR}"/kustomize-select-resource.sh "${KUST_FILE}" -s "${RESOURCE_SELECT}" > ${EDIT_FILE}

# remove patches, build and write _unpatched_ yaml to UNPATCHED_BUILD_FILE
push_unpatched_kustomize "${KUST_FILE}.bak"
"${SCRIPT_DIR}"/kustomize-select-resource.sh "${KUST_FILE}" -s "${RESOURCE_SELECT}" > ${UNPATCHED_BUILD_FILE}
pop_unpatched_kustomize "${KUST_FILE}.bak"

# edit EDIT_FILE
# TODO: why does quoting the tempfile not work?
"${EDITOR:-vi}" ${EDIT_FILE}

if ! cat ${EDIT_FILE} | yq; then
    echo "Error parsing yaml:"
    cat -n ${EDIT_FILE}
    echo ""
    cat ${EDIT_FILE} | yq
    exit 1
fi

# get the diff with jd
PATCHES=$(jd -f patch -yaml ${UNPATCHED_BUILD_FILE} ${EDIT_FILE} | yq -P)

#TODO: only echo of -p specified
echo "patches:"
echo "${PATCHES}"

#TODO: insert (or replace) the single patch matching PATCHES_SELECT _using_ the .kind/.metadata.name from the yaml resource.

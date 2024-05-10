#!/bin/bash

POSITIONAL_ARGS=()

function help {
    ERROR="$1"
    if [ ! -z "${ERROR}" ]; then
        echo "Error: $1"
    fi
    echo "Usage: $0 KUSTOMIZATION_PATH YQ_SELECT"
    echo ""
    echo "  KUSTOMIZATION_PATH - /path/to/kustomization.yaml"
    echo "  -s --yq-select - to be run via yq's select(YQ_SELECT)"
    echo "  -c --count-documents - print document count"
    echo "  -h --help - print this message and exit"
    echo ""
    echo "Examples:"
    echo "  Print the number of Deployment resources and exit"
    echo "    $0 -c $F '.kind == \"Deployment\"'"
    echo ""
    echo "  Output the Deployment named foobar"
    echo "    $0 -c $F '.kind == \"Deployment\" and .metadata.name == \"foobar\"'"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--count-documents)
      DOC_COUNT=1
      shift # past argument
      ;;
    -s|--yq-select)
      YQ_SELECT=$2
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

if [ -z ${KUST_FILE} ]; then
    help "Path to kustomization.yaml not specified"
    exit 1
fi

function build {
    DIR_PATH=$1
    kustomize build --load-restrictor LoadRestrictionsNone ${DIR_PATH}
}

function select_document {
    export QUERY=$1
    yq e '. | select(eval(strenv(QUERY)))'
}

function doc_count {
    yq e '. | kind' | wc -l
}


OUT=$(build "${KUST_DIR}" | select_document "$YQ_SELECT")

if [[ $DOC_COUNT -eq 1 ]]; then
    echo "${OUT}" | doc_count
    exit 0
fi

echo "${OUT}"

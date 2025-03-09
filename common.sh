#!/bin/bash

# common variables

export results_folder="results"
export ovl_folder="ovl"
export auto_setup_alpine_folder="$ovl_folder/etc/auto-setup-alpine"
export overlay_config_folder="ovl-config"

# common functions

get_value_from_collection () {
    local collection_path=${1-}
    local collection_index=${2-}
    local value_name=${3-}
    if [ -z "${collection_path-}" ] || [ -z "${collection_index-}" ] || [ -z "${value_name-}" ]; then
        echo "Usage: get_value_from_collection [collection_path] [collection_index] [value_name]"
        return 1
    fi

    local value;
    value="$(yq eval "$collection_path.$collection_index.$value_name" config.yaml)"
    if [[ "$value" = "null" ]]; then
        value=
    fi
    echo "${value}"
}

collection_any () {
    local collection_path=${1-}
    local collection_index=${2-}
    if [ -z "${collection_path-}" ] || [ -z "${collection_index-}" ]; then
        echo "Usage: collection_any [collection_path] [collection_index]"
        return 1
    fi

    local current_collection;
    current_collection="$(yq eval "$collection_path.$collection_index" config.yaml)"
    if [[ "$current_collection" != "null" ]]; then
        return 0
    else
        return 1
    fi
}

substitute_template () {
    local template_file=${1-}
    local output_file=${2-}

    if [ -z "${template_file-}" ] || [ -z "${output_file-}" ]; then
        echo "Usage: substitute_template [template_file] [output_file]"
        return 1
    fi

    rm -f "$output_file"
    while read -r line
    do
        eval echo "$line" >> "$output_file"
    done < "$template_file"
}

get_value_from_collection_or_default () {
    local collection_path=${1-}
    local collection_index=${2-}
    local value_name=${3-}
    local default=${4-}
    if [[ -z ${1-} || -z ${2-} || -z ${3-} || -z ${4-} ]]; then
        echo "Usage: get_value_from_collection_or_default [collection_path] [collection_index] [value_name] [default]"
        return 1
    fi
    
    local value;
    value="$(get_value_from_collection "$collection_path" "$collection_index" "$value_name")"
    
    value="${value:-$default}"
    echo "$value"
}
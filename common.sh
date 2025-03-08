#!/bin/bash

# common functions

get_value_from_collection () {
    local collection_index=${1-}
    local value_name=${2-}
    if [ -z "${collection_index-}" ] || [ -z "${value_name-}" ]; then
        echo "Usage: get_value_from_collection [collection_index] [value_name]"
        return 1
    fi

    local value="$(yq eval ".setup.$collection_index.$value_name" config.yaml)"
    if [[ "$value" = "null" ]]; then
        value=
    fi
    echo "${value}"
}

collection_any () {
    local collection_index=${1-}
    if [ -z "${collection_index-}" ]; then
        echo "Usage: collection_any [collection_index]"
        return 1
    fi

    local current_collection="$(yq eval ".setup.$collection_index" config.yaml)"
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

    rm -f $output_file
    while read line
    do
        eval echo "$line" >> $output_file
    done < $template_file
}
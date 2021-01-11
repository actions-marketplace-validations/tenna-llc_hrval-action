#!/usr/bin/env bash

set -o errexit

NOT_EXIST_INDICATOR="not-exist"

HELM_RELEASE="${1}"

SERVICE_IMAGE_REPO=$(yq r "${HELM_RELEASE}" spec.values.service.image.repository --defaultValue "${NOT_EXIST_INDICATOR}")
CRON_IMAGE_REPO=$(yq r "${HELM_RELEASE}" spec.values.cron.image.repository --defaultValue "${NOT_EXIST_INDICATOR}")
MIGRATION_IMAGE_REPO=$(yq r "${HELM_RELEASE}" spec.values.migration.image.repository --defaultValue "${NOT_EXIST_INDICATOR}")
echo $SERVICE_IMAGE_REPO
echo $CRON_IMAGE_REPO
echo $MIGRATION_IMAGE_REPO

function check_image_exist {
    local IMAGE_REPO="${1}"
    local IMAGE_TAG="${2}"
    local NON_EXIST_IMAGE="no"
    local __IMAGES_MISSING=$3

    # check if yaml aliases are being used
    if [[ "${IMAGE_REPO}" =~ ^\*.* ]]; then
        IMAGE_REPO=$(evaluate_yaml_alias "${IMAGE_REPO}")
        echo "Found yaml alias ${IMAGE_REPO}"
    fi
    if [[ "${IMAGE_TAG}" =~ ^\*.* ]]; then
        IMAGE_TAG=$(evaluate_yaml_alias "${IMAGE_TAG}")
        echo "Found yaml alias ${IMAGE_TAG}"
    fi

    # repo name should only be the org name with repo name
    if [[ "${IMAGE_REPO}" =~ ^ghcr.io.* ]]; then
        REPO_NAME=$(echo ${IMAGE_REPO} | cut -d'/' -f2-)
    else
        REPO_NAME=$IMAGE_REPO
    fi

    # check if the image exists
    GHCR_TOKEN=$(curl -u ten-chh:1f5a60ffc5d5d4e6821071520d76f26794cc49db https://ghcr.io/token\?scope=\="repository:${IMAGE_REPO}:pull" | jq .token)
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H"Authorization: Bearer ${GHCR_TOKEN}" https://ghcr.io/v2/${REPO_NAME}/manifests/${IMAGE_TAG})

    echo "Status code: ${STATUS_CODE}"
    echo "Repo name: ${REPO_NAME}"
    echo "GHCR token: ${GHCR_TOKEN}"
    echo "curl -s -o /dev/null -w "%{http_code}" -H"Authorization: Bearer "${GHCR_TOKEN}"" https://ghcr.io/v2/${REPO_NAME}/manifests/${IMAGE_TAG}"

    if [[ "${STATUS_CODE}" == "200" ]]; then
        NON_EXIST_IMAGE="no"
    else
        NON_EXIST_IMAGE="yes"
    fi

    echo "Validating ${IMAGE_REPO}:${IMAGE_TAG}. Is the image missing? ${NON_EXIST_IMAGE}"

    eval $__IMAGES_MISSING="${NON_EXIST_IMAGE}"
}

function evaluate_yaml_alias {
    local YAML_ALIAS="${1}"
    local YAML_ALIAS_KEY=$(echo "${YAML_ALIAS}" | tr "*" "&")

    grep "${YAML_ALIAS_KEY}" "${HELM_RELEASE}" | cut -d '"' -f2
}

function validate_images {

    local IMAGES_MISSING="no"

    # check spec.values.service exists
    if [[ "${SERVICE_IMAGE_REPO}" != "${NOT_EXIST_INDICATOR}" ]]; then
        echo "Processing service image"
        SERVICE_IMAGE_TAG=$(yq r "${HELM_RELEASE}" spec.values.service.image.tag --defaultValue "${NOT_EXIST_INDICATOR}")
        check_image_exist "${SERVICE_IMAGE_REPO}" "${SERVICE_IMAGE_TAG}" IMAGES_MISSING
    fi

    # check spec.values.cron exists
    if [[ "${CRON_IMAGE_REPO}" != "${NOT_EXIST_INDICATOR}" ]]; then
        echo "Processing cron image"
        CRON_IMAGE_TAG=$(yq r "${HELM_RELEASE}" spec.values.cron.image.tag --defaultValue "${NOT_EXIST_INDICATOR}")
        check_image_exist "${CRON_IMAGE_REPO}" "${CRON_IMAGE_TAG}" IMAGES_MISSING
    fi

    # check spec.values.migration exists
    if [[ "${MIGRATION_IMAGE_REPO}" != "${NOT_EXIST_INDICATOR}" ]]; then
        echo "Processing migration image"
        MIGRATION_IMAGE_TAG=$(yq r "${HELM_RELEASE}" spec.values.migration.image.tag --defaultValue "${NOT_EXIST_INDICATOR}")
        check_image_exist "${MIGRATION_IMAGE_REPO}" "${MIGRATION_IMAGE_TAG}" IMAGES_MISSING
    fi

    echo "Are there non-existent images in the Helm Release? ${IMAGES_MISSING}"
    if [[ "${IMAGES_MISSING}" == "yes" ]]; then exit 1; else exit 0; fi
}

validate_images
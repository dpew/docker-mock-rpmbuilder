#!/usr/bin/bash
set -ex


MOCK_BIN="/usr/bin/mock"
MOCK_CONF_FOLDER="/etc/mock"
MOCK_RESULTS_FOLDER=/mockresults
MOCK_OUTPUT_FOLDER="${MOCK_RESULTS_FOLDER}/output"
CACHE_FOLDER="${MOCK_RESULTS_FOLDER}/cache"
# shellcheck disable=SC2206
MOCK_DEFINES=(${MOCK_DEFINES})
DEF_SIZE="${#MOCK_DEFINES[@]}"
OWNERSHIP=${OWNERSHIP:-$(id -u mockbuilder):$(id -g mockbuilder)}

RESULTS_FOLDER="${MOUNT_POINT}/output"

post_results() {
   if [ -d "$MOCK_OUTPUT_FOLDER" ] ; then
     chown -R "${OWNERSHIP}" "${MOCK_OUTPUT_FOLDER}"
     cp -rp "${MOCK_OUTPUT_FOLDER}" "${RESULTS_FOLDER}"
   fi
}

trap post_results EXIT

if [ "${DEF_SIZE}" -gt 0 ]
  then
    for ((i=0; i < DEF_SIZE; i++));
      do
        # shellcheck disable=SC2116
        DEFINE_CMD+=" --define '$(echo "${MOCK_DEFINES[$i]//=/ }")'"
      done
fi

if [ -z "${MOCK_CONFIG}" ]
  then
    echo "MOCK_CONFIG is empty. Should bin one of: "
    ls -l "${MOCK_CONF_FOLDER}"
elif [ ! -f "${MOCK_CONF_FOLDER}/${MOCK_CONFIG}.cfg" ]
  then
    echo "MOCK_CONFIG is invalid. Should bin one of: "
    ls -l "${MOCK_CONF_FOLDER}"
elif [ -z "${SOURCE_RPM}" ] && [ -z "${SPEC_FILE}" ]
  then
    echo "Please provide the src.rpm or spec file to build"
    echo "Set SOURCE_RPM or SPEC_FILE environment variables"
    exit 1
fi

if [ -n "${NO_CLEANUP}" ]
  then
    echo "WARNING: Disabling clean up of the build folder after build"
fi

# If proxy env variable is set, add the proxy value to the configuration file
if [ -n "${HTTP_PROXY}" ] || [ -n "${http_proxy}" ]
  then
    TEMP_PROXY=""
    if [ -n "${HTTP_PROXY}" ]
      then
        TEMP_PROXY=$(echo "${HTTP_PROXY}" | sed s/\\//\\\\\\//g)
    fi

    if [ -n "${http_proxy}" ]
      then
        TEMP_PROXY=$(echo "${http_proxy}" | sed s/\\//\\\\\\//g)
    fi

    echo "Configuring http proxy to the mock build file to: ${TEMP_PROXY}"
    cp "/etc/mock/${MOCK_CONFIG}.cfg" "/tmp/$MOCK_CONFIG.cfg"
    sed s/\\[main\\]/\[main\]\\\nproxy="${TEMP_PROXY}"/g \
"/tmp/${MOCK_CONFIG}.cfg" > "/etc/mock/${MOCK_CONFIG}.cfg"

fi

OUTPUT_FOLDER="${MOCK_OUTPUT_FOLDER}/${MOCK_CONFIG}"
rm -rf "${OUTPUT_FOLDER}"
MOCK_CONFIG_OPTS="--config-opts='cache_topdir=${CACHE_FOLDER}'"
mkdir -p "${OUTPUT_FOLDER}"
chown -R mockbuilder:mock "${OUTPUT_FOLDER}"
mkdir -p "${CACHE_FOLDER}"
chown -R mockbuilder:mock "${CACHE_FOLDER}"

if [ -n "${NETWORK}" ]
  then
    MOCK_CONFIG_OPTS="${MOCK_CONFIG_OPTS} --enable-network"
fi


echo "=> Building parameters:"
echo "================================================================="
echo "   MOCK_CONFIG:      ${MOCK_CONFIG}"

# Priority to SOURCE_RPM if both source and spec file env variable are set
if [ -n "${SOURCE_RPM}" ]
  then
    echo "   SOURCE_RPM:        ${SOURCE_RPM}"
    echo "   OUTPUT_FOLDER:     -e${OUTPUT_FOLDER}"
    echo "================================================================="

    if [ -n "${NO_CLEANUP}" ]
      then
        echo "${MOCK_BIN} ${MOCK_CONFIG_OPTS} ${DEFINE_CMD} -r ${MOCK_CONFIG} \
--rebuild ${MOUNT_POINT}/${SOURCE_RPM} --resultdir=${OUTPUT_FOLDER} \
--no-clean" > "${OUTPUT_FOLDER}/build-script.sh"
    else
      echo "${MOCK_BIN} ${MOCK_CONFIG_OPTS} ${DEFINE_CMD} -r ${MOCK_CONFIG} \
--rebuild ${MOUNT_POINT}/${SOURCE_RPM} --resultdir=${OUTPUT_FOLDER}" > \
"${OUTPUT_FOLDER}/build-script.sh"
    fi

elif [ -n "${SPEC_FILE}" ]
  then
    if [ -z "${SOURCES}" ]
      then
        SOURCES="sources"
        mkdir -p "${MOUNT_POINT}/${SOURCES}"
    fi

        echo "   SPEC_FILE:        ${SPEC_FILE}"
        echo "   SOURCES:          ${SOURCES}"
        echo "   OUTPUT_FOLDER:    ${OUTPUT_FOLDER}"
        echo "   MOCK_DEFINES:     ${MOCK_DEFINES[*]}"
        echo "   MOCK_CONFIG_OPTS: ${MOCK_CONFIG_OPTS[*]}"
        echo "================================================================="

        BUILD_COMMAND="${MOCK_BIN} ${MOCK_CONFIG_OPTS} ${DEFINE_CMD} -r \
${MOCK_CONFIG} --buildsrpm --spec=${MOUNT_POINT}/${SPEC_FILE} \
--resultdir=${OUTPUT_FOLDER} --sources=${MOUNT_POINT}/${SOURCES}"
        REBUILD_COMMAND="${MOCK_BIN} ${MOCK_CONFIG_OPTS} ${DEFINE_CMD} -r \
${MOCK_CONFIG} --rebuild \$(find ${OUTPUT_FOLDER} -type f -name \"*.src.rpm\") \
--resultdir=${OUTPUT_FOLDER}"

        if [ -n "${NO_CLEANUP}" ]
          then
          # do not cleanup chroot between both mock calls as 1st does not alter
          # it
            BUILD_COMMAND="${BUILD_COMMAND} --no-cleanup-after"
            REBUILD_COMMAND="${REBUILD_COMMAND} --no-clean"
        fi

        {
          echo "set -e"
          echo "${BUILD_COMMAND}"
          echo "${REBUILD_COMMAND}"
        } >> "${OUTPUT_FOLDER}/build-script.sh"
fi

if [[ "${SOURCES}" == "sources" ]]
  then
    /usr/bin/rpmbuild --nobuild --define "_topdir ${MOUNT_POINT}/${SOURCES}" \
--define "_sourcedir ${MOUNT_POINT}/${SOURCES}" \
--define "source_date_epoch_from_changelog false" \
--undefine "_disable_source_fetch" "${MOUNT_POINT}/${SPEC_FILE}"
fi

chmod 755 "${OUTPUT_FOLDER}/build-script.sh"
sudo -u mockbuilder "${OUTPUT_FOLDER}/build-script.sh" 2> /dev/stderr

rm "${OUTPUT_FOLDER}/build-script.sh"

if [ -n "${SIGNATURE}" ]
  then
    echo "%_signature gpg" > "${HOME}/.rpmmacros"
    echo "%_gpg_name ${SIGNATURE}" >> "${HOME}/.rpmmacros"
    echo "Signing RPM using ${SIGNATURE} key"
    find "${OUTPUT_FOLDER}" -type f -name "*.rpm" -exec /rpm-sign.exp {} \
"${GPG_PASS}" \;
else
  echo "No RPMs signature requested"
fi


echo "Build finished. Check results inside 'output' directory"

#!/bin/bash
# 合并后的构建脚本，支持APK和XAPK格式 (已适配最新纯so库版MOD)
# 公共变量参数 部分从Github Action中传入
BUILD_TOOLS_DIR=$(find ${ANDROID_HOME}/build-tools -maxdepth 1 -type d | sort -V | tail -n 1)
AAPT_PATH="${BUILD_TOOLS_DIR}/aapt"
DOWNLOAD_DIR="."
GAME_SERVER=$1
APK_URL=$2
BUILD_TYPE="APK" # 默认构建类型

# 检查参数
CHECK_PARAM() {
    if [ -z "${GAME_SERVER}" ]; then
        echo "服务器名称不能为空"
        exit 1
    fi

    if ! echo "${GAME_SERVER}" | grep -q "^[a-zA-Z0-9]*$"; then
        echo "服务器参数包含非英文数字字符,请重新输入"
        exit 1
    fi

    case "${GAME_SERVER}" in
        "TW" | "EN" | "JP" | "KR")
            BUILD_TYPE="XAPK"
            echo "检测到需要使用XAPK构建模式: ${GAME_SERVER}"
            ;;
        *)
            if [ -z "${APK_URL}" ]; then
                echo "APK下载链接不能为空"
                exit 1
            fi
            BUILD_TYPE="APK"
            echo "使用标准APK构建模式: ${GAME_SERVER}"
            ;;
    esac
}

# 设置包名和文件名
SET_BUNDLE_ID() {
    case "$GAME_SERVER" in
        "TW") GAME_BUNDLE_ID="com.hkmanjuu.azurlane.gp" ;;
        "EN") GAME_BUNDLE_ID="com.YoStarEN.AzurLane" ;;
        "JP") GAME_BUNDLE_ID="com.YoStarJP.AzurLane" ;;
        "KR") GAME_BUNDLE_ID="kr.txwy.and.blhx" ;;
    esac
    APK_FILENAME="${GAME_BUNDLE_ID}.apk"
    echo "已设置包名为: ${GAME_BUNDLE_ID}"
}

# 下载apkeep
DOWNLOAD_APKEEP() {
    local OWNER="EFForg"
    local REPO="apkeep"
    local LIB_PLATFORM="x86_64-unknown-linux-gnu"
    local FILENAME="apkeep"

    echo "正在下载apkeep工具..."
    local API_RESPONSE=$(curl -s "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest")
    local DOWNLOAD_LINK=$(echo "${API_RESPONSE}" | jq -r ".assets[] | select(.name | contains(\"${LIB_PLATFORM}\")) | .browser_download_url" | head -n 1)
    if [ -z "${DOWNLOAD_LINK}" ] || [ "${DOWNLOAD_LINK}" == "null" ]; then
        echo "无法找到Apkeep下载链接"
        exit 1
    fi

    curl -L -o "${DOWNLOAD_DIR}/${FILENAME}" "${DOWNLOAD_LINK}"
    chmod +x "${DOWNLOAD_DIR}/${FILENAME}"
}

# 下载ApkTool
DOWNLOAD_APKTOOL() {
    local OWNER="iBotPeaches"
    local REPO="Apktool"
    local FILENAME="apktool.jar"

    echo "正在下载Apktool..."
    local API_RESPONSE=$(curl -s "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest")
    local DOWNLOAD_LINK=$(echo "${API_RESPONSE}" | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -n 1)
   
    if [ -z "${DOWNLOAD_LINK}" ] || [ "${DOWNLOAD_LINK}" == "null" ]; then
        echo "无法找到Apktool下载链接"
        exit 1
    fi

    curl -L -o "${DOWNLOAD_DIR}/${FILENAME}" "${DOWNLOAD_LINK}"
}

# 下载 Mod Patch 文件并解压
DOWNLOAD_MOD_MENU() {
    local OWNER="JMBQ"
    local REPO="azurlane"
    local FILENAME="MOD_MENU.rar"

    echo "正在下载MOD补丁..."
    local API_RESPONSE=$(curl -s "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest")
    local JMBQ_VERSION=$(echo "${API_RESPONSE}" | jq -r '.tag_name')
    local DOWNLOAD_LINK=$(echo "${API_RESPONSE}" | jq -r '.assets[] | select(.name | contains(".rar")) | .browser_download_url' | head -n 1)

    if [ -z "${DOWNLOAD_LINK}" ] || [ "${DOWNLOAD_LINK}" == "null" ]; then
        local FILENAME="MOD_MENU.zip"
        local DOWNLOAD_LINK=$(echo "${API_RESPONSE}" | jq -r '.assets[] | select(.name | contains(".zip")) | .browser_download_url' | head -n 1)
        if [ -z "${DOWNLOAD_LINK}" ] || [ "${DOWNLOAD_LINK}" == "null" ]; then
            echo "无法获取MOD Patch文件下载链接"
            exit 1
        fi
    fi

    curl -L -o "${DOWNLOAD_DIR}/${FILENAME}" "${DOWNLOAD_LINK}"

    if command -v 7z &> /dev/null; then
        7z x -y "${DOWNLOAD_DIR}/${FILENAME}" -o"${DOWNLOAD_DIR}/JMBQ"
    else
        echo "错误: 未找到7z工具，无法解压！"
        exit 1
    fi
    echo "JMBQ_VERSION=${JMBQ_VERSION}" >> "${GITHUB_ENV}"
}

# 下载APK
DOWNLOAD_APK() {
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        echo "正在使用apkeep下载XAPK..."
        "${DOWNLOAD_DIR}/apkeep" -a "${GAME_BUNDLE_ID}" "${DOWNLOAD_DIR}/"
        unzip -o "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk" -d "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}"
        mv "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}/${GAME_BUNDLE_ID}.apk" "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_FILENAME="${GAME_SERVER}.apk"
        echo "正在下载APK..."
        curl -L -o "${DOWNLOAD_DIR}/${APK_FILENAME}" "${APK_URL}"
        if [ $? -ne 0 ]; then
            echo "APK下载失败"
            exit 1
        fi
    fi
}

DELETE_ORGINAL_XAPK() {
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        rm -rf "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk"
    fi
}

VERIFY_APK() {
    local APK_TO_VERIFY
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_VERIFY="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_VERIFY="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    local FILE_SIZE=$(stat -f%z "${APK_TO_VERIFY}" 2>/dev/null || stat -c%s "${APK_TO_VERIFY}" 2>/dev/null)
    [ "${FILE_SIZE}" -lt 1024 ] && { echo "APK文件大小异常，可能是下载链接失效或被拦截"; exit 1; }
    echo "APK验证通过"
}

DECODE_APK() {
    local APK_TO_DECODE
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_DECODE="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_DECODE="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    echo "APK反编译: ${APK_TO_DECODE}"
    java -jar "${DOWNLOAD_DIR}/apktool.jar" d -f "${APK_TO_DECODE}" -o "${DOWNLOAD_DIR}/DECODE_Output"
    echo "反编译完成。"
}

DELETE_ORGINAL_APK() {
    local APK_TO_DELETE
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_DELETE="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_DELETE="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    rm -rf "${APK_TO_DELETE}"
}

# ==========================================
# 核心修复部分：全新的补丁合入逻辑 (仅覆盖so文件)
# ==========================================
PATCH_APK() {
    echo "正在合入纯 .so 架构补丁..."
    
    # 将解压出来的下划线目录内容，覆盖到反编译后的中划线lib目录下
    if [ -d "${DOWNLOAD_DIR}/JMBQ/arm64_v8a" ]; then
        echo "合入 arm64-v8a 补丁..."
        mkdir -p "${DOWNLOAD_DIR}/DECODE_Output/lib/arm64-v8a"
        cp -rf "${DOWNLOAD_DIR}/JMBQ/arm64_v8a/"* "${DOWNLOAD_DIR}/DECODE_Output/lib/arm64-v8a/"
    fi

    if [ -d "${DOWNLOAD_DIR}/JMBQ/x86" ]; then
        echo "合入 x86 补丁..."
        mkdir -p "${DOWNLOAD_DIR}/DECODE_Output/lib/x86"
        cp -rf "${DOWNLOAD_DIR}/JMBQ/x86/"* "${DOWNLOAD_DIR}/DECODE_Output/lib/x86/"
    fi

    if [ -d "${DOWNLOAD_DIR}/JMBQ/x86_64" ]; then
        echo "合入 x86_64 补丁..."
        mkdir -p "${DOWNLOAD_DIR}/DECODE_Output/lib/x86_64"
        cp -rf "${DOWNLOAD_DIR}/JMBQ/x86_64/"* "${DOWNLOAD_DIR}/DECODE_Output/lib/x86_64/"
    fi

    echo "补丁合入完成！"
}
# ==========================================

BUILD_APK() {
    local OUTPUT_APK
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        OUTPUT_APK="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        OUTPUT_APK="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    echo "正在重新构建已打补丁的 APK 文件..."
    java -jar "${DOWNLOAD_DIR}/apktool.jar" b -f "${DOWNLOAD_DIR}/DECODE_Output" -o "${OUTPUT_APK}"
    echo "APK 构建成功"
}

OPTIMIZE_AND_SIGN_APK() {
    export PATH=${PATH}:${BUILD_TOOLS_DIR}
    local KEY_DIR="${DOWNLOAD_DIR}/key/"
    local PRIVATE_KEY="${KEY_DIR}testkey.pk8"
    local CERTIFICATE="${KEY_DIR}testkey.x509.pem"
    local INPUT_APK
    local UNSIGNED_APK
    local FINAL_APK
    
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        INPUT_APK="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
        UNSIGNED_APK="${GAME_BUNDLE_ID}.unsigned.apk"
    else
        INPUT_APK="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
        UNSIGNED_APK="${GAME_SERVER}.unsigned.apk"
    fi
    
    local OUTPUT_APK="${DOWNLOAD_DIR}/${UNSIGNED_APK}"
    local FINAL_APK="${INPUT_APK}"

    echo "正在优化并签名APK..."
    zipalign -f 4 "${INPUT_APK}" "${OUTPUT_APK}"
    rm "${INPUT_APK}"
    apksigner sign --key "${PRIVATE_KEY}" --cert "${CERTIFICATE}" "${OUTPUT_APK}"
    mv "${OUTPUT_APK}" "${FINAL_APK}"
    echo "签名完成！"
}

GET_GAME_VERSION() {
    local APK_TO_CHECK
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        APK_TO_CHECK="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk"
    else
        APK_TO_CHECK="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
    fi
    
    GAME_VERSION=$("${AAPT_PATH}" dump badging "${APK_TO_CHECK}" | grep "versionName" | sed "s/.*versionName='\([^']*\)'.*/\1/" | head -1)
    if [ -z "${GAME_VERSION}" ] || [ "${GAME_VERSION}" = "''" ]; then
        GAME_VERSION="未知"
    fi
    echo "VERSION=${GAME_VERSION}" >> "${GITHUB_ENV}"
}

RENAME_APK() {
    if [ "${BUILD_TYPE}" = "APK" ] && [ -f "${DOWNLOAD_DIR}/${GAME_SERVER}.apk" ]; then
        PACKAGE_NAME=$("${AAPT_PATH}" dump badging "${DOWNLOAD_DIR}/${GAME_SERVER}.apk" | grep "package: name=" | cut -d"'" -f2 | head -1)
        if [ -z "${PACKAGE_NAME}" ] || [ "${PACKAGE_NAME}" = "''" ]; then
            PACKAGE_NAME="${GAME_SERVER}"
        fi
        mv "${DOWNLOAD_DIR}/${GAME_SERVER}.apk" "${DOWNLOAD_DIR}/${PACKAGE_NAME}.apk"
    fi
}

REPACK_XAPK() {
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        mkdir -p "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}"
        mv -f "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.apk" "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}/${GAME_BUNDLE_ID}.apk"
        cd "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}" && zip -r "${GAME_BUNDLE_ID}.xapk" *
        cd - > /dev/null
        mv "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}/${GAME_BUNDLE_ID}.xapk" "${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk"
    fi
}

CREATE_SPLIT_ARCHIVES() {
    local FINAL_FILE
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        FINAL_FILE="${DOWNLOAD_DIR}/${GAME_BUNDLE_ID}.xapk"
    else
        if [ -f "${DOWNLOAD_DIR}/${PACKAGE_NAME}.apk" ]; then
            FINAL_FILE="${DOWNLOAD_DIR}/${PACKAGE_NAME}.apk"
        else
            FINAL_FILE="${DOWNLOAD_DIR}/${GAME_SERVER}.apk"
        fi
    fi
    echo "正在压缩分卷 ${FINAL_FILE}"
    7z a -v800M "${GAME_SERVER}-V.${GAME_VERSION}.7z" "${FINAL_FILE}"
}

main() {
    CHECK_PARAM
    if [ "${BUILD_TYPE}" = "XAPK" ]; then
        SET_BUNDLE_ID
        DOWNLOAD_APKEEP
        DOWNLOAD_APKTOOL
        DOWNLOAD_MOD_MENU
        DOWNLOAD_APK
        DELETE_ORGINAL_XAPK
        VERIFY_APK
        DECODE_APK
        DELETE_ORGINAL_APK
        PATCH_APK
        BUILD_APK
        OPTIMIZE_AND_SIGN_APK
        GET_GAME_VERSION
        REPACK_XAPK
    else
        DOWNLOAD_APKTOOL
        DOWNLOAD_MOD_MENU
        DOWNLOAD_APK
        VERIFY_APK
        DECODE_APK
        DELETE_ORGINAL_APK
        PATCH_APK
        BUILD_APK
        OPTIMIZE_AND_SIGN_APK
        GET_GAME_VERSION
        RENAME_APK
    fi
    CREATE_SPLIT_ARCHIVES
    echo "全自动打包构建已完成！"
}

main

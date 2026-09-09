#!/usr/bin/env bash

# 运行方式
# ./local-build.sh --cache-dir ./build-cache/
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALLER_DIR="$(pwd)"

RELEASE_REPO="${COSTRICT_RELEASE_REPO:-zgsm-sangfor/builder}"
PACKAGES_ARCHIVE=""
OUTPUT_DIR="${SCRIPT_DIR}/artifact-local"
CACHE_DIR="${COSTRICT_CACHE_DIR:-${SCRIPT_DIR}/local-build-cache}"
REPACK=true
KEEP_WORKDIR=false
REFRESH_CACHE=false
OFFLINE=false
CACHE_ONLY=false
WORK_DIR=""

STATIC_BASE_URL="${COSTRICT_STATIC_BASE_URL:-https://zgsm.sangfor.com}"
SMC_VERSION="${COSTRICT_SMC_VERSION:-1.1.18}"
SMC_URL="${COSTRICT_SMC_URL:-https://zgsm.sangfor.com/costrict/smc/linux/amd64/${SMC_VERSION}/smc}"

log() {
    printf '[local-build] %s\n' "$*"
}

die() {
    printf '[local-build] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./local-build.sh [options]

Build the same two artifacts produced by .github/workflows/build.yaml without
building, pulling, saving, or packaging service Docker images.

Options:
  --packages-archive FILE  Use an existing packages.tar.gz as the package base
                           instead of downloading the latest GitHub Release.
  --repo OWNER/REPO        Release repository (default: zgsm-sangfor/builder).
  --output-dir DIR         Artifact output directory (default: artifact-local).
  --cache-dir DIR          Persistent download cache (default: local-build-cache).
  --refresh-cache          Refresh cached downloads before building.
  --offline                Never access the network; fail if cache is incomplete.
  --cache-only             Prepare the cache and exit without building artifacts.
  --assemble-only          Reuse signed packages without rebuilding components.
                           This does not require smc or costrict-private.pem.
  --keep-workdir           Keep the temporary build directory for inspection.
  -h, --help               Show this help.

Environment:
  GH_TOKEN or GITHUB_TOKEN is used when the Release repository is private.

Default mode rebuilds and signs component packages from the current working
tree. It reuses prebuilt executable packages from the latest Release and only
updates Docker image references; it never invokes docker or clones services.

Downloaded packages, executable Release assets, smc, Docker/Compose/jq
installers, and the nginx image are kept under the cache directory. Later
builds reuse them without downloading.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --packages-archive)
            [[ $# -ge 2 ]] || die "--packages-archive requires a file"
            PACKAGES_ARCHIVE="$2"
            shift 2
            ;;
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires OWNER/REPO"
            RELEASE_REPO="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a directory"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --cache-dir)
            [[ $# -ge 2 ]] || die "--cache-dir requires a directory"
            CACHE_DIR="$2"
            shift 2
            ;;
        --refresh-cache)
            REFRESH_CACHE=true
            shift
            ;;
        --offline)
            OFFLINE=true
            shift
            ;;
        --cache-only)
            CACHE_ONLY=true
            shift
            ;;
        --assemble-only)
            REPACK=false
            shift
            ;;
        --keep-workdir)
            KEEP_WORKDIR=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1 (run --help for usage)"
            ;;
    esac
done

if [[ "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="${CALLER_DIR}/${OUTPUT_DIR}"
fi
if [[ "$CACHE_DIR" != /* ]]; then
    CACHE_DIR="${CALLER_DIR}/${CACHE_DIR#./}"
fi
if [[ "$CACHE_DIR" != / ]]; then
    CACHE_DIR="${CACHE_DIR%/}"
fi
if [[ "$OFFLINE" == true && "$REFRESH_CACHE" == true ]]; then
    die "--offline and --refresh-cache cannot be used together"
fi

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        if [[ "$KEEP_WORKDIR" == true ]]; then
            log "Temporary build directory kept at: $WORK_DIR"
        else
            rm -rf "$WORK_DIR"
        fi
    fi
}
trap cleanup EXIT

release_token() {
    if [[ -n "${GH_TOKEN:-}" ]]; then
        printf '%s' "$GH_TOKEN"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        printf '%s' "$GITHUB_TOKEN"
    fi
}

download_packages_with_curl() {
    local target="$1"
    local token
    local release_json
    local asset_url
    local direct_url="https://github.com/${RELEASE_REPO}/releases/latest/download/packages.tar.gz"
    local curl_args=(-fL --retry 3 --retry-delay 2 --connect-timeout 20)

    require_command curl
    token="$(release_token)"
    if [[ -n "$token" ]]; then
        curl_args+=(-H "Authorization: Bearer ${token}")
    fi

    log "Downloading latest packages.tar.gz from ${RELEASE_REPO}..."
    if curl "${curl_args[@]}" -o "$target" "$direct_url"; then
        return 0
    fi

    # Private repositories may reject the browser download URL. Resolve the
    # asset through the GitHub API and retry with the binary media type.
    rm -f "$target"
    release_json="${WORK_DIR}/release.json"
    if ! curl "${curl_args[@]}" \
        -H "Accept: application/vnd.github+json" \
        -o "$release_json" \
        "https://api.github.com/repos/${RELEASE_REPO}/releases/latest"; then
        die "failed to query the latest Release; set GH_TOKEN for a private repository"
    fi

    asset_url="$(jq -r 'first(.assets[] | select(.name == "packages.tar.gz") | .url) // empty' "$release_json")"
    [[ -n "$asset_url" && "$asset_url" != null ]] || \
        die "latest Release does not contain packages.tar.gz"

    curl "${curl_args[@]}" \
        -H "Accept: application/octet-stream" \
        -o "$target" "$asset_url" || \
        die "failed to download packages.tar.gz from the latest Release"
}

obtain_packages_archive() {
    local target="$1"
    local cache_archive="${CACHE_DIR}/packages/packages.tar.gz"
    local download_dir="${WORK_DIR}/release-download"
    local downloaded_archive="${download_dir}/packages.tar.gz"

    if [[ -n "$PACKAGES_ARCHIVE" ]]; then
        [[ -f "$PACKAGES_ARCHIVE" ]] || die "package archive not found: $PACKAGES_ARCHIVE"
        log "Using package base: $PACKAGES_ARCHIVE"
        validate_packages_archive "$PACKAGES_ARCHIVE"
        mkdir -p "$(dirname "$cache_archive")"
        if [[ ! "$PACKAGES_ARCHIVE" -ef "$cache_archive" ]]; then
            cp "$PACKAGES_ARCHIVE" "$cache_archive"
        fi
        cp "$PACKAGES_ARCHIVE" "$target"
        return
    fi

    if [[ -f "$cache_archive" && "$REFRESH_CACHE" != true ]]; then
        log "Using cached package base: $cache_archive"
        cp "$cache_archive" "$target"
        return
    fi

    if [[ "$OFFLINE" == true ]]; then
        die "cached packages.tar.gz is missing; prepare the cache without --offline first"
    fi

    mkdir -p "$download_dir"
    if command -v gh >/dev/null 2>&1; then
        log "Downloading latest packages.tar.gz from ${RELEASE_REPO} with gh..."
        if gh release download \
            --repo "$RELEASE_REPO" \
            --pattern packages.tar.gz \
            --dir "$download_dir" \
            --clobber; then
            validate_packages_archive "$downloaded_archive"
            mkdir -p "$(dirname "$cache_archive")"
            cp "$downloaded_archive" "$cache_archive"
            cp "$cache_archive" "$target"
            return
        fi
        log "gh download failed; retrying with curl"
    fi

    download_packages_with_curl "$downloaded_archive"
    validate_packages_archive "$downloaded_archive"
    mkdir -p "$(dirname "$cache_archive")"
    cp "$downloaded_archive" "$cache_archive"
    cp "$cache_archive" "$target"
}

validate_packages_archive() {
    local archive="$1"
    local listing="${WORK_DIR}/packages-archive.list"

    tar -tzf "$archive" > "$listing" || die "invalid gzip tar archive: $archive"
    grep -q '^packages/' "$listing" || die "archive does not contain a packages/ directory"
    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$listing"; then
        die "archive contains an unsafe path"
    fi
}

download_url() {
    local url="$1"
    local target="$2"
    local temporary="${target}.part"

    [[ "$OFFLINE" != true ]] || die "offline mode cannot download: $url"
    require_command curl
    mkdir -p "$(dirname "$target")"
    if [[ -s "$temporary" ]]; then
        log "Resuming partial download: $temporary"
    fi
    if ! curl -fL -C - \
        --retry 10 --retry-all-errors --retry-delay 3 --connect-timeout 20 \
        -o "$temporary" "$url"; then
        die "download failed; partial file kept for retry: $temporary"
    fi
    mv "$temporary" "$target"
}

prepare_smc_cache() {
    local smc_dir="${CACHE_DIR}/tools/smc/linux/amd64/${SMC_VERSION}"
    local cached_smc="${smc_dir}/smc"
    local installed_smc=""

    if [[ -x "$cached_smc" && "$REFRESH_CACHE" != true ]]; then
        log "Using cached smc: $cached_smc"
    elif [[ "$OFFLINE" == true ]]; then
        die "cached smc is missing: $cached_smc"
    else
        mkdir -p "$smc_dir"
        if [[ "$REFRESH_CACHE" != true ]]; then
            installed_smc="$(command -v smc 2>/dev/null || true)"
        fi
        if [[ -n "$installed_smc" && -x "$installed_smc" ]]; then
            log "Caching installed smc from: $installed_smc"
            cp "$installed_smc" "$cached_smc"
        else
            log "Downloading smc ${SMC_VERSION} into the cache..."
            download_url "$SMC_URL" "$cached_smc"
        fi
        chmod +x "$cached_smc"
    fi

    export PATH="$smc_dir:$PATH"
}

static_cache_complete() {
    local static_dir="$1"
    local manifest="${static_dir}/MANIFEST"
    local file_path

    [[ -s "$manifest" ]] || return 1
    while IFS= read -r file_path || [[ -n "$file_path" ]]; do
        file_path="$(printf '%s' "$file_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$file_path" || "$file_path" == \#* ]] && continue
        file_path="${file_path#./}"
        [[ "$file_path" == "MANIFEST" || "$file_path" == "mirror-site.tar" ]] && continue
        [[ -s "${static_dir}/${file_path}" ]] || return 1
    done < "$manifest"
    [[ -s "${static_dir}/nginx-1.31.1.tar" ]]
}

prepare_static_cache() {
    local static_cache="${CACHE_DIR}/costrict-static"
    local manifest
    local file_path

    if [[ "$REFRESH_CACHE" != true ]] && static_cache_complete "$static_cache"; then
        log "Using cached Docker/Compose/jq installers and nginx image: $static_cache"
        return
    fi
    if [[ "$OFFLINE" == true ]]; then
        die "costrict-static cache is incomplete: $static_cache"
    fi

    mkdir -p "$static_cache"
    cp -a "$SCRIPT_DIR/costrict-static/." "$static_cache/"
    manifest="${static_cache}/MANIFEST"
    [[ -s "$manifest" ]] || die "local costrict-static/MANIFEST is missing"

    while IFS= read -r file_path || [[ -n "$file_path" ]]; do
        file_path="$(printf '%s' "$file_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$file_path" || "$file_path" == \#* ]] && continue
        file_path="${file_path#./}"
        [[ "$file_path" == *".."* ]] && die "unsafe path in costrict-static MANIFEST: $file_path"
        [[ "$file_path" == "MANIFEST" || "$file_path" == "mirror-site.tar" ]] && continue
        if [[ ! -s "${static_cache}/${file_path}" || "$REFRESH_CACHE" == true ]]; then
            log "Caching static asset: $file_path"
            download_url \
                "${STATIC_BASE_URL}/costrict-static/${file_path}" \
                "${static_cache}/${file_path}"
        fi
    done < "$manifest"

    if [[ ! -s "${static_cache}/nginx-1.31.1.tar" || "$REFRESH_CACHE" == true ]]; then
        log "${static_cache}/nginx-1.31.1.tar no found. Caching nginx image..."
        download_url \
            "${STATIC_BASE_URL}/costrict-static/nginx-1.31.1.tar" \
            "${static_cache}/nginx-1.31.1.tar"
    fi

    static_cache_complete "$static_cache" || die "downloaded costrict-static cache is incomplete"
    log "Static asset cache prepared: $static_cache"
}

copy_build_inputs() {
    local destination="$1"
    local item

    mkdir -p "$destination"
    for item in "$SCRIPT_DIR"/*.sh; do
        [[ -f "$item" ]] && cp -a "$item" "$destination/"
    done
    for item in \
        components configures depends site costrict-static \
        latest.json packages.json costrict-manifest.json costrict-backend-spec.json; do
        [[ -e "$SCRIPT_DIR/$item" ]] && cp -a "$SCRIPT_DIR/$item" "$destination/"
    done

    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp -a "$SCRIPT_DIR/.env" "$destination/.env"
    else
        : > "$destination/.env"
    fi

    if [[ "$REPACK" == true ]]; then
        [[ -f "$SCRIPT_DIR/costrict-private.pem" ]] || \
            die "costrict-private.pem is required; use --assemble-only to reuse existing signatures"
        cp -a "$SCRIPT_DIR/costrict-private.pem" "$destination/costrict-private.pem"
    fi
}

prepare_prebuilt_executables() {
    local packages_root="$1"
    local config
    local name
    local version
    local remote
    local repo
    local os
    local arch
    local filename
    local package_file
    local cached_file

    for config in "$SCRIPT_DIR"/depends/*.json; do
        [[ -f "$config" ]] || continue
        if [[ "$(jq -r '.type' "$config")" != exec ]] || \
           [[ "$(jq -r 'if .enabled == false or .enabled == "false" then "false" else "true" end' "$config")" != true ]]; then
            continue
        fi

        name="$(jq -r '.name' "$config")"
        version="$(jq -r '.version' "$config")"
        remote="$(jq -r '.remote // empty' "$config")"
        repo="$(printf '%s' "$remote" | sed \
            -e 's#^git@github.com:##' \
            -e 's#^https://github.com/##' \
            -e 's#\.git$##')"
        [[ -n "$repo" ]] || die "cannot determine GitHub repository for executable: $name"

        while IFS=$'\t' read -r os arch; do
            [[ -n "$os" && -n "$arch" ]] || continue
            filename="$name"
            [[ "$os" == windows ]] && filename="${filename}.exe"
            package_file="${packages_root}/${name}/${os}/${arch}/${version}/${filename}"
            cached_file="${CACHE_DIR}/executables/${name}/${os}/${arch}/${version}/${filename}"

            if [[ -s "$package_file" && "$REFRESH_CACHE" != true ]]; then
                if [[ ! -s "$cached_file" ]]; then
                    mkdir -p "$(dirname "$cached_file")"
                    cp "$package_file" "$cached_file"
                fi
                continue
            fi

            if [[ -s "$cached_file" && "$REFRESH_CACHE" != true ]]; then
                log "Using cached executable: ${name} ${os}/${arch} v${version}"
            elif [[ "$OFFLINE" == true ]]; then
                die "cached executable is missing: $cached_file"
            else
                log "Downloading executable Release asset: ${name} ${os}/${arch} v${version}"
                mkdir -p "$(dirname "$cached_file")"
                bash "$SCRIPT_DIR/github-fetch-release.sh" \
                    --repo "$repo" \
                    --package "$name" \
                    --os "$os" \
                    --arch "$arch" \
                    --version "$version" \
                    --output "$cached_file"
            fi

            [[ -s "$cached_file" ]] || die "executable download is empty: $cached_file"
            mkdir -p "$(dirname "$package_file")"
            cp "$cached_file" "$package_file"
            chmod +x "$package_file" 2>/dev/null || true
        done < <(jq -r '.platforms[] | [.os, .arch] | @tsv' "$config")
    done
}

check_prebuilt_executables() {
    local config
    local name
    local version
    local os
    local arch
    local package_dir
    local missing=()

    for config in depends/*.json; do
        [[ -f "$config" ]] || continue
        if [[ "$(jq -r '.type' "$config")" != exec ]] || \
           [[ "$(jq -r 'if .enabled == false or .enabled == "false" then "false" else "true" end' "$config")" != true ]]; then
            continue
        fi

        name="$(jq -r '.name' "$config")"
        version="$(jq -r '.version' "$config")"
        while IFS=$'\t' read -r os arch; do
            [[ -n "$os" && -n "$arch" ]] || continue
            package_dir="packages/${name}/${os}/${arch}/${version}"
            if [[ ! -d "$package_dir" ]] || \
               ! find "$package_dir" -maxdepth 1 -type f \
                   ! -name package.json ! -name platform.json -print -quit | grep -q .; then
                missing+=("${name}/${os}/${arch}/${version}")
            fi
        done < <(jq -r '.platforms[] | [.os, .arch] | @tsv' "$config")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '[local-build] Missing prebuilt executable package:\n' >&2
        printf '  %s\n' "${missing[@]}" >&2
        die "the package base does not match current depends versions; refresh the cache"
    fi
}

update_docker_references() {
    local docker_packages

    docker_packages="$(
        for config in depends/*.json; do
            [[ -f "$config" ]] || continue
            jq -r 'select(
                .type == "docker" and
                (.enabled != false and .enabled != "false")
            ) | input_filename' "$config"
        done | sed -e 's#^depends/##' -e 's#\.json$##' | paste -sd, -
    )"

    if [[ -n "$docker_packages" ]]; then
        log "Updating Docker image references without pulling or building images..."
        ./build-depends.sh --update --packages "$docker_packages"
    fi
}

assemble_mirror_from_cache() {
    local static_cache="${CACHE_DIR}/costrict-static"

    static_cache_complete "$static_cache" || die "costrict-static cache is incomplete"
    mkdir -p costrict-static
    cp -a "$static_cache/." costrict-static/

    [[ -d site ]] || die "site directory not found"
    tar -cf costrict-static/mirror-site.tar -C site .
    tar -czf costrict-mirror.tar.gz costrict-static packages
}

build_artifacts() {
    local build_dir="$1"
    local mirror_listing="${WORK_DIR}/mirror.list"

    cd "$build_dir"
    tar --no-same-owner -xzf "$WORK_DIR/packages.tar.gz"
    [[ -d packages ]] || die "packages directory was not extracted"

    if [[ "$REPACK" == true ]]; then
        prepare_prebuilt_executables packages
        check_prebuilt_executables
        update_docker_references
        log "Rebuilding and signing enabled component packages..."
        ./build-costrict.sh --pack all
    else
        log "Assemble-only mode: keeping component packages from the Release"
    fi

    cp packages.json packages/packages.json
    log "Building costrict-mirror.tar.gz from cached static assets..."
    assemble_mirror_from_cache

    tar -tzf costrict-mirror.tar.gz > "$mirror_listing"
    if grep -q '^images/' "$mirror_listing"; then
        die "costrict-mirror.tar.gz unexpectedly contains service images"
    fi
    grep -q '^costrict-static/' "$mirror_listing" || \
        die "costrict-mirror.tar.gz does not contain costrict-static"
    grep -q '^packages/' "$mirror_listing" || \
        die "costrict-mirror.tar.gz does not contain packages"

    mkdir -p "$OUTPUT_DIR"
    tar -czf "$WORK_DIR/packages-output.tar.gz" packages
    cp "$WORK_DIR/packages-output.tar.gz" "$OUTPUT_DIR/packages.tar.gz"
    cp costrict-mirror.tar.gz "$OUTPUT_DIR/costrict-mirror.tar.gz"
}

main() {
    local archive
    local build_dir

    require_command jq
    require_command tar
    require_command sed
    require_command grep
    require_command paste
    require_command find
    if [[ "$REPACK" == true && "$CACHE_ONLY" != true ]]; then
        require_command zip
    fi

    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/costrict-local-build.XXXXXX")"
    archive="${WORK_DIR}/packages.tar.gz"
    build_dir="${WORK_DIR}/builder"

    obtain_packages_archive "$archive"
    validate_packages_archive "$archive"
    if [[ "$REPACK" == true || "$CACHE_ONLY" == true ]]; then
        prepare_smc_cache
        mkdir -p "${WORK_DIR}/cache-packages"
        tar --no-same-owner -xzf "$archive" -C "${WORK_DIR}/cache-packages"
        prepare_prebuilt_executables "${WORK_DIR}/cache-packages/packages"
    fi
    prepare_static_cache

    if [[ "$CACHE_ONLY" == true ]]; then
        log "Cache prepared: $CACHE_DIR"
        log "Run with --offline to build without network access."
        return
    fi

    copy_build_inputs "$build_dir"
    build_artifacts "$build_dir"

    log "Build completed. Artifacts:"
    log "  ${OUTPUT_DIR}/packages.tar.gz"
    log "  ${OUTPUT_DIR}/costrict-mirror.tar.gz"
    log "Service Docker images were not built, pulled, saved, or packaged."
}

main "$@"

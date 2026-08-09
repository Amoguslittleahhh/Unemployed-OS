#!/usr/bin/env bash
# Runs a script passed via the `script=` kernel command-line parameter,
# for unattended/automated live-session setups.
#
# Hardened vs. upstream releng's version (see Unemployed OS issue #2):
#   - only https:// or a local path is accepted -- plain http/ftp/tftp are
#     refused outright, since an unauthenticated transport gives an
#     on-path attacker arbitrary code execution in the live root session
#   - a remote (https://) script MUST be paired with a `script_sha256=`
#     kernel parameter naming its expected SHA-256; content that doesn't
#     match is never executed
#   - the download lands in a mktemp'd, 0700 file instead of the
#     predictable /tmp/startup_script, so another local user (or process)
#     can't pre-place/symlink that path
#   - curl no longer follows redirects (--proto '=https', no --location),
#     so a compromised/misconfigured redirect can't silently swap in a
#     different, unverified payload after the sha256 the user was told to
#     pin

script_cmdline() {
    local param
    for param in $(</proc/cmdline); do
        case "${param}" in
            script=*)
                echo "${param#*=}"
                return 0
                ;;
        esac
    done
}

script_sha256_cmdline() {
    local param
    for param in $(</proc/cmdline); do
        case "${param}" in
            script_sha256=*)
                echo "${param#*=}"
                return 0
                ;;
        esac
    done
}

automated_script() {
    local script rt tmp_script expected_sha256 actual_sha256
    local marker="/tmp/.automated_script_ran"

    script="$(script_cmdline)"
    [[ -n "${script}" && ! -e "${marker}" ]] || return 0

    tmp_script="$(mktemp /tmp/startup_script.XXXXXX)"
    chmod 700 "${tmp_script}"

    if [[ "${script}" =~ ^https:// ]]; then
        printf '%s: downloading %s\n' "$0" "${script}"
        # there's no synchronization for network availability before executing this script; to ensure the network
        # is online, we use a transient systemd service that depends on network-online.target to download the
        # script rather than manually polling the target
        systemd-run --pty --quiet -p Wants=network-online.target -p After=network-online.target \
            curl "${script}" --proto '=https' --retry-connrefused --retry 10 --fail -s -o "${tmp_script}"
        rt=$?
    elif [[ "${script}" =~ ^((http|ftp|tftp)://) ]]; then
        printf '%s: refusing %s -- only https:// (with a matching script_sha256=) or a local path is supported\n' "$0" "${script}" >&2
        rm -f "${tmp_script}"
        return 1
    else
        cp "${script}" "${tmp_script}"
        rt=$?
    fi

    if [[ ${rt} -ne 0 ]]; then
        rm -f "${tmp_script}"
        return "${rt}"
    fi

    if [[ "${script}" =~ ^https:// ]]; then
        expected_sha256="$(script_sha256_cmdline)"
        actual_sha256="$(sha256sum "${tmp_script}" | cut -d' ' -f1)"
        if [[ -z "${expected_sha256}" ]]; then
            printf '%s: refusing to execute %s -- no script_sha256= given on the kernel cmdline (expected %s)\n' \
                "$0" "${script}" "${actual_sha256}" >&2
            rm -f "${tmp_script}"
            return 1
        fi
        if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
            printf '%s: script_sha256 mismatch for %s (expected %s, got %s), refusing to execute\n' \
                "$0" "${script}" "${expected_sha256}" "${actual_sha256}" >&2
            rm -f "${tmp_script}"
            return 1
        fi
    fi

    # Only gate against retries once we're committed to executing -- a
    # transient download/copy/checksum failure above should be retryable
    # on the next tty1 login, not permanently locked out.
    touch "${marker}"
    chmod +x "${tmp_script}"
    printf '%s: executing automated script\n' "$0"
    # note that script is executed when other services (like pacman-init) may be still in progress, please
    # synchronize to "systemctl is-system-running --wait" when your script depends on other services
    "${tmp_script}"
    rt=$?
    rm -f "${tmp_script}"
    return "${rt}"
}

if [[ $(tty) == "/dev/tty1" ]]; then
    automated_script
fi

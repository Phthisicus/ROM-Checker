#!/usr/bin/env bash
# Ubuntu/WSL bootstrap. Keep this file beside RomSorter.ps1.
set -Eeuo pipefail

fail() { printf 'RomSorter setup: %s\n' "$*" >&2; exit 1; }
if [[ ${1:-} == --help ]]; then
    printf '%s\n' \
        'Usage: bash RomSorter.sh [RomSorter PowerShell arguments...]' \
        '       bash RomSorter.sh --install-only' \
        '' \
        'Installs missing Ubuntu prerequisites, verifies antivirus readiness, then starts RomSorter.' \
        'Uses sudo only for installation/signature updates; RomSorter runs as your current user.' \
        'Requires internet access for installation. Existing working components are reused.' \
        'Example: bash RomSorter.sh -RootFolder "/mnt/c/Users/you/Downloads/Roms"'
    exit 0
fi
install_only=false
if [[ ${1:-} == --install-only ]]; then
    [[ $# == 1 ]] || fail '--install-only cannot be combined with ROM actions.'
    install_only=true
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ -f "$script_dir/RomSorter.ps1" ]] || fail 'Put RomSorter.sh and RomSorter.ps1 in the same folder.'
[[ -r /etc/os-release ]] || fail 'This launcher supports Ubuntu/WSL only.'
. /etc/os-release
[[ ${ID:-} == ubuntu ]] || fail 'This launcher supports Ubuntu/WSL only; it will not change this distribution.'
[[ $(dpkg --print-architecture) == amd64 ]] || fail 'Automatic PowerShell installation currently supports Ubuntu amd64 (x86-64) only.'

work=$(mktemp -d "${TMPDIR:-/tmp}/romsorter-setup.XXXXXXXX")
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "RomSorter setup failed at line %s. No ROM action was started.\n" "$LINENO" >&2' ERR

root_ready=false
as_root() {
    if [[ $(id -u) == 0 ]]; then "$@"; return; fi
    command -v sudo >/dev/null || fail 'sudo is required to install missing packages. Ask your system administrator to enable it.'
    if ! $root_ready; then
        printf '%s\n' 'Missing components need administrator access. Enter your Ubuntu password if prompted.'
        sudo -v || fail 'Administrator permission was not granted. Nothing will be scanned or sorted.'
        root_ready=true
    fi
    sudo -- "$@"
}
apt_updated=false
update_apt() {
    if ! $apt_updated; then
        as_root apt-get -o DPkg::Lock::Timeout=120 update
        apt_updated=true
    fi
}
install_packages() {
    update_apt
    as_root apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends "$@"
}
powershell_ready() {
    command -v pwsh >/dev/null &&
        pwsh -NoLogo -NoProfile -NonInteractive -Command \
            'if ($PSVersionTable.PSVersion.Major -lt 7 -or [IO.Path]::DirectorySeparatorChar -ne "/") { exit 1 }' \
            >"$work/powershell.log" 2>&1
}
archive_ready() { command -v 7zz >/dev/null || command -v 7z >/dev/null || command -v 7za >/dev/null; }

if ! powershell_ready; then
    printf '%s\n' 'Installing PowerShell 7 from the official Microsoft PowerShell GitHub release.'
    install_packages ca-certificates curl
    # Pinned official package and GitHub release SHA-256; never execute a downloaded setup script.
    package="$work/powershell_7.6.7-1.deb_amd64.deb"
    curl --fail --location --show-error --proto '=https' --proto-redir '=https' \
        --retry 3 --connect-timeout 30 --max-time 900 \
        https://github.com/PowerShell/PowerShell/releases/download/v7.6.7/powershell_7.6.7-1.deb_amd64.deb \
        --output "$package"
    printf '%s  %s\n' '868c575f0822b2deed054c1c3c464a9d4b841f67e153369147fb6ace3545c8b2' "$package" | sha256sum --check -
    chmod 755 "$work"
    chmod 644 "$package"
    # apt resolves .NET native dependencies, including the ICU version provided by this Ubuntu release.
    install_packages "$package"
    hash -r
    if ! powershell_ready; then
        if [[ -f "$work/powershell.log" ]]; then cat "$work/powershell.log" >&2; fi
        fail 'PowerShell was installed but cannot run.'
    fi
fi

if ! command -v clamscan >/dev/null || ! command -v freshclam >/dev/null; then
    printf '%s\n' 'Installing ClamAV and its signature updater.'
    install_packages clamav clamav-freshclam
    hash -r
fi
if ! archive_ready; then
    update_apt
    if apt-cache show 7zip >/dev/null 2>&1; then archive_package=7zip
    elif apt-cache show p7zip-full >/dev/null 2>&1; then archive_package=p7zip-full
    else fail 'Neither 7zip nor p7zip-full is available in your Ubuntu repositories. Check your repository configuration.'; fi
    printf 'Installing archive support (%s).\n' "$archive_package"
    install_packages "$archive_package"
    hash -r
fi
command -v clamscan >/dev/null || fail 'ClamAV installation did not provide clamscan.'
command -v freshclam >/dev/null || fail 'ClamAV installation did not provide freshclam.'
archive_ready || fail '7-Zip installation did not provide 7zz, 7z or 7za.'
archive_tool=$(command -v 7zz || command -v 7z || command -v 7za)
"$archive_tool" i >"$work/archive.log" 2>&1 ||
    { cat "$work/archive.log" >&2; fail '7-Zip is present but cannot run.'; }

printf '%s\n' 'Checking ClamAV and its signature database (no ROMs are scanned during setup).'
printf '%s\n' 'RomSorter harmless antivirus readiness check.' >"$work/antivirus-probe.txt"
antivirus_ready() { clamscan --no-summary "$work/antivirus-probe.txt" >"$work/antivirus.log" 2>&1; }
if ! antivirus_ready; then
    printf '%s\n' 'ClamAV is not ready. Initial virus-signature downloads can take several minutes.'
    if command -v systemctl >/dev/null && systemctl is-active --quiet clamav-freshclam; then
        printf '%s\n' 'The existing signature-update service is running; waiting up to five minutes without interrupting it.'
        for ((attempt=0; attempt<20; attempt++)); do
            if antivirus_ready; then break; fi
            sleep 15
        done
    else
        as_root freshclam --stdout ||
            fail 'ClamAV signatures could not be updated. Check internet access and the updater output above, then rerun this launcher.'
    fi
    antivirus_ready ||
        { cat "$work/antivirus.log" >&2; fail 'Antivirus is still not ready. No ROM action was started; resolve the displayed error and rerun.'; }
fi

printf '%s\n' 'Ready: PowerShell 7, ClamAV with a usable signature database, and 7-Zip.'
if $install_only; then exit 0; fi
cleanup
trap - EXIT ERR INT TERM
exec pwsh -NoLogo -NoProfile -File "$script_dir/RomSorter.ps1" "$@"

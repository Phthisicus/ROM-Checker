#!/usr/bin/env bash
set -euo pipefail
# Run only on an isolated CI runner; credentials and data are disposable fixtures.
sudo apt-get update -qq
sudo apt-get install -y -qq samba > /dev/null
sudo systemctl stop smbd nmbd
sudo useradd --no-create-home romfixture
printf 'fixture-only-smb-password\nfixture-only-smb-password\n' | sudo smbpasswd -a -s romfixture
fixture="${RUNNER_TEMP:?}/romchecker-smb"
mkdir -p "$fixture/roms/Games/Nested" "$fixture/state" "$fixture/private"
python3 - "$fixture/roms/Fixture.nes" <<'PY'
import sys
data = bytearray(40976)
data[:6] = bytes([0x4e, 0x45, 0x53, 0x1a, 2, 1])
with open(sys.argv[1], 'wb') as file:
    file.write(data)
PY
cp "$fixture/roms/Fixture.nes" "$fixture/roms/Games/Nested/Fixture.nes"
chmod 755 "$fixture" "$fixture/roms"
chmod 644 "$fixture/roms/Fixture.nes"
chmod 755 "$fixture/roms/Games" "$fixture/roms/Games/Nested"
chmod 644 "$fixture/roms/Games/Nested/Fixture.nes"
cat > "$fixture/smb.conf" <<EOF
[global]
server role = standalone server
interfaces = 127.0.0.1
bind interfaces only = yes
server min protocol = SMB2
map to guest = Never
log file = $fixture/smb.log
[roms]
path = $fixture/roms
read only = yes
valid users = romfixture
force user = $(id -un)
EOF
sudo smbd --daemon --configfile="$fixture/smb.conf"

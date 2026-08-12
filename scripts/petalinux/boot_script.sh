#!/bin/bash
# Install a project's boot_script.sh so it runs once at boot.
# Arguments: <board_name> <board_version> <project_name>
#
# If the project ships a top-level `boot_script.sh`, this wraps it in a small
# sysvinit service (a meta-user "boot-script" app recipe) that is enabled in the
# rootfs, so the script runs at every boot. This is the udev-free hook for things
# that must happen once the kernel and its autoloaded modules are up -- e.g.
# relaxing a root-owned /dev node's mode. No-op if the project has no such file.
if [ $# -ne 3 ]; then
  echo "[PTLNX BOOT SCRIPT] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name>"
  exit 1
fi

# Store the positional parameters in named variables and clear them
BRD=${1}
VER=${2}
PRJ=${3}
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"
set --

# If any subsequent command fails, exit immediately
set -e

# Validate the project's boot script (regular, executable file) if present.
./scripts/check/boot_script.sh ${BRD} ${VER} ${PRJ}

# The project's boot script (optional). Nothing to do if it doesn't exist.
BOOT_SCRIPT="${ZYNQ_TOOLBOX}/projects/${PRJ}/boot_script.sh"
if [ ! -f "${BOOT_SCRIPT}" ]; then
  echo "[PTLNX BOOT SCRIPT] No boot script to install for ${PBV}"
  echo " Path: projects/${PRJ}/boot_script.sh"
  exit 0
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
if [ -z "$PETALINUX" ]; then
  source ${PETALINUX_PATH}/settings.sh
fi

# Enter the PetaLinux project directory
cd tmp/${BRD}/${VER}/${PRJ}/petalinux

APP="boot-script"
echo "[PTLNX BOOT SCRIPT] Installing boot script as app: ${APP}"

# Create (and enable) the app recipe. --enable adds it to the rootfs image, so
# the init script is actually installed. The "install" template just installs a
# data file; we overwrite the generated recipe and files below.
petalinux-create apps --name ${APP} --template install --enable --force

APP_DIR="project-spec/meta-user/recipes-apps/${APP}"
FILES_DIR="${APP_DIR}/files"

# Replace the template payload: the project's boot script plus an init.d wrapper
# that runs it on "start". Keeping the user's script a plain script (invoked by
# the wrapper) means projects don't have to write LSB start/stop boilerplate.
rm -f "${FILES_DIR}"/*
cp -f "${BOOT_SCRIPT}" "${FILES_DIR}/boot_script.sh"

cat > "${FILES_DIR}/${APP}" <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          boot-script
# Required-Start:    $all
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Run the project's boot_script.sh at boot
### END INIT INFO

case "$1" in
  start)
    [ -x /usr/bin/boot_script.sh ] && /usr/bin/boot_script.sh
    ;;
  stop|restart|reload|force-reload|status)
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
EOF

# Recipe: install both files and register the init script via update-rc.d so it
# is linked into the runlevels and runs at boot. CLOSED license avoids requiring
# a license-file checksum for this generated, project-local recipe.
cat > "${APP_DIR}/${APP}.bb" <<'EOF'
#
# boot-script: installs projects/<project>/boot_script.sh and runs it at boot.
# Auto-generated and managed by scripts/petalinux/boot_script.sh -- do not edit
# by hand; edit the project's boot_script.sh instead.
#
SUMMARY = "Run the project's boot_script.sh at boot"
LICENSE = "CLOSED"

SRC_URI = "file://boot_script.sh \
           file://boot-script"

S = "${WORKDIR}"

inherit update-rc.d

INITSCRIPT_NAME = "boot-script"
INITSCRIPT_PARAMS = "defaults 99"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/boot_script.sh ${D}${bindir}/boot_script.sh

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/boot-script ${D}${sysconfdir}/init.d/boot-script
}

FILES:${PN} += "${sysconfdir}/init.d/boot-script ${bindir}/boot_script.sh"
EOF

echo "[PTLNX BOOT SCRIPT] Boot script installed and enabled for ${PBV}"

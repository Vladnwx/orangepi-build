#!/usr/bin/env bash
#
# Unisoc/AW859A (uwe5622) WiFi/BT driver for the mainline kernel.
#
# The vendor kernel ships this driver in-tree; upstream Linux does not. The
# community-maintained tree at github.com/armbian/uwe5622 is kept building
# against recent kernels (verified against 7.2 with no source changes), so it is
# fetched and added to the kernel tree right before the build.
#
# The firmware (/lib/firmware/wifi_2355b001_1ant.ini and wcnmodem.bin) already
# comes from the orangepi-firmware package.
#
# Enabled only for the sun50iw9 mainline branch, where the vendor kernel does
# not already provide the driver.

declare -g UWE5622_REPO="https://github.com/armbian/uwe5622"
# Pinned: bump deliberately, the driver is out-of-tree vendor code.
declare -g UWE5622_COMMIT="cc2835a3f935d5297e03cdce464c1785381a7b4d"
declare -g UWE5622_SRC="${EXTER}/cache/sources/uwe5622"

# Fetch the driver once, next to the other sources.
function fetch_sources_tools__uwe5622() {
	fetch_from_repo "${UWE5622_REPO}" "${UWE5622_SRC}" "commit:${UWE5622_COMMIT}"
}

# Add the driver to the kernel tree and enable it, before olddefconfig runs.
function custom_kernel_config__uwe5622() {
	local kdir="${kerneldir:-$(pwd)}"
	local dst="${kdir}/drivers/net/wireless/uwe5622"

	[[ -d ${UWE5622_SRC} ]] || exit_with_error "uwe5622: driver sources are missing" "${UWE5622_SRC}"

	display_alert "Adding uwe5622 WiFi/BT driver to the kernel" "${UWE5622_COMMIT:0:12}" "info"

	rm -rf "${dst}"
	mkdir -p "${dst}"
	cp -a "${UWE5622_SRC}"/. "${dst}/"

	# Build all three parts as modules.
	#
	# The driver's Kconfig declares SPARD_WLAN_SUPPORT and AW_WIFI_DEVICE_UWE5622
	# as bool and pulls the WCN core into vmlinux with obj-y. The core requests
	# firmware when it probes, which a built-in driver does before the root
	# filesystem is mounted, so the vendor kernel builds it as a module and the
	# build system loads it from /etc/modules after boot. Make the two symbols
	# tristate and use obj-m so the same happens here.
	python3 - "${dst}" <<'PYEOF'
import re
import sys

dst = sys.argv[1]

# SPARD_WLAN_SUPPORT: bool -> tristate (top level Kconfig)
path = f"{dst}/Kconfig"
s = open(path).read()
s = re.sub(r'(config SPARD_WLAN_SUPPORT\n\t)bool ', r'\1tristate ', s, count=1)
open(path, "w").write(s)

# AW_WIFI_DEVICE_UWE5622: bool -> tristate
path = f"{dst}/unisocwcn/Kconfig"
s = open(path).read()
s = re.sub(r'(config AW_WIFI_DEVICE_UWE5622\n\t)bool ', r'\1tristate ', s, count=1)
open(path, "w").write(s)

# obj-y -> obj-m for the WCN core
path = f"{dst}/Makefile"
s = open(path).read()
old = ("ifneq ($(CONFIG_AW_WIFI_DEVICE_UWE5622)$(CONFIG_RK_WIFI_DEVICE_UWE5622),)\n"
       "obj-y += unisocwcn/\n"
       "endif\n")
new = ("obj-$(CONFIG_AW_WIFI_DEVICE_UWE5622) += unisocwcn/\n"
       "obj-$(CONFIG_RK_WIFI_DEVICE_UWE5622) += unisocwcn/\n")
if old not in s:
    sys.exit("uwe5622: unexpected top-level Makefile, cannot switch unisocwcn to a module")
s = s.replace(old, new, 1)
open(path, "w").write(s)
PYEOF
	[[ $? -eq 0 ]] || exit_with_error "uwe5622: failed to adapt the driver build files" ""

	# Hook the driver into the wireless Kconfig/Makefile
	grep -q 'uwe5622/Kconfig' "${kdir}/drivers/net/wireless/Kconfig" || \
		echo 'source "drivers/net/wireless/uwe5622/Kconfig"' >> "${kdir}/drivers/net/wireless/Kconfig"
	grep -q 'uwe5622/' "${kdir}/drivers/net/wireless/Makefile" || \
		echo 'obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/' >> "${kdir}/drivers/net/wireless/Makefile"

	# Enable the driver (the kernel config is in place at this point)
	local cfg="${kdir}/scripts/config"
	"${cfg}" --file "${kdir}/.config" \
		--module SPARD_WLAN_SUPPORT \
		--module WLAN_UWE5622 \
		--module TTY_OVERY_SDIO \
		--enable CFG80211 \
		--enable WLAN \
		--enable RFKILL
}

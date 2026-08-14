# SPDX-License-Identifier: GPL-2.0
# Optional Waveshare 5-DSI-TOUCH-A display profile for BeagleY-AI.

_waveshare_5dsi_target()
{
    [[ "${BOARD:-}" == "beagley-ai" && "${BRANCH:-}" == "vendor" ]]
}

function extension_prepare_config__waveshare_5dsi_packages()
{
    _waveshare_5dsi_target || return 0

    local package
    for package in xinput x11-xserver-utils evtest i2c-tools; do
        add_packages_to_image "$package"
    done
}

# This hook runs after Armbian has reset/cleaned and patched the kernel tree.
# Copying the display sources here makes CLEAN_LEVEL=make-kernel deterministic.
function custom_kernel_config__waveshare_5dsi_kernel()
{
    _waveshare_5dsi_target || return 0

    kernel_config_modifying_hashes+=("waveshare-5dsi-ti-k3-r1")

    # config-dump/version-calculation calls do not have a live kernel .config.
    [[ -f .config ]] || return 0

    local payload="${SRC}/userpatches/waveshare-5dsi/kernel"
    [[ -d "$payload" ]] || exit_with_error \
        "Waveshare kernel payload is missing" "$payload"

    install -D -m 0644 \
        "$payload/drivers/gpu/drm/panel/panel-waveshare-5-dsi-touch-a.c" \
        "$kernel_work_dir/drivers/gpu/drm/panel/panel-waveshare-5-dsi-touch-a.c"
    install -D -m 0644 \
        "$payload/drivers/regulator/waveshare-panel-regulator.c" \
        "$kernel_work_dir/drivers/regulator/waveshare-panel-regulator.c"
    install -D -m 0644 \
        "$payload/drivers/input/touchscreen/waveshare-gt911-poll.c" \
        "$kernel_work_dir/drivers/input/touchscreen/waveshare-gt911-poll.c"
    install -D -m 0644 \
        "$payload/arch/arm64/boot/dts/ti/k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtso" \
        "$kernel_work_dir/arch/arm64/boot/dts/ti/k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtso"

    opts_y+=(DRM_CDNS_DSI_J721E)
    opts_m+=(
        DRM_CDNS_DSI
        PHY_CADENCE_DPHY
        DRM_PANEL_WAVESHARE_5_DSI_TOUCH_A
        WAVESHARE_PANEL_MCU
        TOUCHSCREEN_WAVESHARE_GT911_POLL
    )
}

function post_customize_image__waveshare_5dsi_install()
{
    _waveshare_5dsi_target || return 0

    local payload="${SRC}/userpatches/waveshare-5dsi/rootfs"
    [[ -d "$payload" ]] || exit_with_error \
        "Waveshare rootfs payload is missing" "$payload"

    display_alert "Installing Waveshare 5-DSI target payload" "${EXTENSION}" "info"
    rsync -a --chown=0:0 "$payload/" "${SDCARD}/"

    install -d -m 0755 "${SDCARD}/etc/systemd/system/graphical.target.wants"
    ln -sfn ../waveshare-display-ready.service \
        "${SDCARD}/etc/systemd/system/graphical.target.wants/waveshare-display-ready.service"

    local source_dtb="" candidate target_dtb backup_dtb
    for candidate in \
        "${SDCARD}/boot/dtb/ti/k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtb" \
        "${SDCARD}/boot/firmware/dtb/ti/k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtb" \
        "${SDCARD}/boot/dtbs/"*/ti/k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtb
    do
        [[ -f "$candidate" ]] || continue
        source_dtb="$candidate"
        break
    done

    [[ -n "$source_dtb" ]] || exit_with_error \
        "Continuous-clock Waveshare DTB was not produced" \
        "k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtb"

    # The composite starts from k3-am67a-beagley-ai.dtb after the TI K3
    # userpatch override has compiled the qualified R3 memory contract into it.
    # Only the display overlay is then merged; no generic EdgeAI overlay is used.
    target_dtb="${source_dtb%/*}/k3-am67a-beagley-ai.dtb"
    backup_dtb="${target_dtb}.before-waveshare"
    [[ -f "$target_dtb" ]] || exit_with_error \
        "Stock BeagleY-AI DTB pathname is missing" "$target_dtb"

    if [[ ! -f "$backup_dtb" ]]; then
        cp -a "$target_dtb" "$backup_dtb"
    fi
    install -m 0644 "$source_dtb" "$target_dtb"
    cmp -s "$source_dtb" "$target_dtb" || exit_with_error \
        "Failed to install continuous-clock DTB" "$target_dtb"

    install -d -m 0755 "${SDCARD}/var/lib/ti-k3-display"
    cat >"${SDCARD}/var/lib/ti-k3-display/waveshare-5dsi.env" <<EOF_DISPLAY
format=1
board=beagley-ai
display=waveshare-5-dsi-touch-a
profile=continuous-clock
base_memory_contract=j722s-beagley-ai-4gb-r73341
target_dtb=${target_dtb#${SDCARD}}
qualification_status=unqualified_display_candidate
EOF_DISPLAY
}

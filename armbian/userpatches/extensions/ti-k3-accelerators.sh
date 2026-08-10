# Armbian extension for generic TI K3 accelerators on BeagleY-AI.

function post_family_config__ti_k3_accelerators() {
    [[ "${BOARD:-}" == "beagley-ai" ]] || return 0
    add_packages_to_image \
        v4l-utils \
        gstreamer1.0-tools \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav
    INSTALL_HEADERS="yes"
    INSTALL_ARMBIAN_FIRMWARE="yes"
}

function user_config__ti_k3_accelerators() {
    [[ "${BOARD:-}" == "beagley-ai" ]] || return 0
    INSTALL_HEADERS="yes"
    INSTALL_ARMBIAN_FIRMWARE="yes"
}

function custom_kernel_config__ti_k3_accelerators() {
    [[ "${BOARD:-}" == "beagley-ai" ]] || return 0
    local cma_mb="${TI_K3_CMA_MBYTES:-256}"
    kernel_config_modifying_hashes+=("ti-k3-accelerators-v1-cma-${cma_mb}")
    opts_y+=(
        MEDIA_SUPPORT MEDIA_CONTROLLER VIDEO_DEV V4L2_FWNODE V4L2_ASYNC
        V4L_MEM2MEM_DRIVERS DMA_CMA DMABUF_HEAPS DMABUF_HEAPS_CARVEOUT
        DMA_BUF_PHYS MULTIPLEXER MUX_GPIO FW_LOADER
    )
    opts_m+=(VIDEO_WAVE_VPU VIDEO_IMX219 VIDEO_CADENCE_CSI2RX VIDEO_TI_J721E_CSI2RX)
    opts_val["CMA_SIZE_MBYTES"]="${cma_mb}"
}

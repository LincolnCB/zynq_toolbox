# ---------------------------------------------------------------------------
# zynq_toolbox Vivado runner
#
# OS-level environment Vivado needs to run in batch mode. Does NOT contain
# Vivado itself -- that's installed once into the `vivado-tools` volume
# (see scripts/docker/install-vivado.sh), then mounted read-only here at runtime.
# This image never needs network access at runtime -- Vivado batch builds
# (synth/impl/bitstream) don't reach out to the internet.
# ---------------------------------------------------------------------------

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
# Match to your host user so files written into the bind-mounted repo aren't
# owned by a random UID. Pass at build time with
# --build-arg BUILD_UID=$(id -u) --build-arg BUILD_GID=$(id -g)
ARG BUILD_UID=1000
ARG BUILD_GID=1000

RUN ln -sf /bin/bash /bin/sh

# Vivado batch mode still links against some X11/font libs even headless,
# plus the usual libncurses/libtinfo runtime Xilinx tools expect.
#
# This image also doubles as the install-time container for the AMD/Xilinx
# unified installer (see install-vivado.sh) -- no separate throwaway image
# for that anymore. python3 through lsb-release below are packages the
# installer itself needs (its own scripting dependencies); they're not
# needed for headless `vivado -mode batch` runs, but keeping one image
# covers both without a second package list to keep in sync.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libncurses5-dev \
    libtinfo5 \
    libxext6 \
    libxtst6 \
    libxi6 \
    libxrender1 \
    libsm6 \
    libice6 \
    fontconfig \
    libfreetype6 \
    locales \
    make \
    ca-certificates \
    python3 \
    xz-utils \
    xterm \
    autoconf \
    libtool \
    texinfo \
    zlib1g-dev \
    gcc-multilib \
    build-essential \
    less \
    rsync \
    bc \
    lsb-release \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# GUI-only extras (for `make vivado_gui`; not needed for headless batch builds).
# The GUI runs against a self-contained X server + VNC inside the container
# (TigerVNC + fluxbox + noVNC), viewable from any host via a browser or VNC
# client. Mesa provides software OpenGL (llvmpipe); no host GPU is required.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    libglu1-mesa \
    tigervnc-standalone-server \
    tigervnc-common \
    fluxbox \
    novnc \
    websockify \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Workaround for a known libudev bug that crashes under Docker: Vivado's
# license manager / WebTalk telemetry calls udev_enumerate_scan_devices()
# to gather host info, which corrupts the glibc heap in containers
# ("mremap_chunk(): invalid pointer", SIGABRT). Forcing libudev to be the
# first library loaded avoids the corrupt allocator state that triggers it.
# Set as an image-wide ENV (not just in a launch script) because
# launch_runs spawns child processes that each need it too.
ENV LD_PRELOAD=/lib/x86_64-linux-gnu/libudev.so.1

RUN groupadd -g ${BUILD_GID} builder \
    && useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash builder

USER builder
WORKDIR /workspace

COPY --chown=builder:builder entrypoint-vivado.sh /home/builder/entrypoint.sh
RUN chmod +x /home/builder/entrypoint.sh

ENTRYPOINT ["/home/builder/entrypoint.sh"]
CMD ["/bin/bash"]

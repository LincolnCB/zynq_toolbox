# ---------------------------------------------------------------------------
# zynq_toolbox build environment
#
# Provides the OS-level environment PetaLinux and Vivado need to run
# (bash-as-default-shell, required apt packages, non-root build user).
# Does NOT contain the Xilinx tools themselves -- those are installed once
# into the separate `xilinx-tools` Docker volume (see docker/README.md),
# then mounted read-only into containers started from this image.
# ---------------------------------------------------------------------------

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
# Match to your host user so files written into bind-mounted volumes (the
# repo, build outputs) aren't owned by a random UID. Pass at build time
# with --build-arg BUILD_UID=$(id -u) --build-arg BUILD_GID=$(id -g)
ARG BUILD_UID=1000
ARG BUILD_GID=1000

# PetaLinux requires /bin/sh -> bash, not dash (Ubuntu's default). Baking
# this into the image means nobody has to do this step by hand.
RUN ln -sf /bin/bash /bin/sh

# Packages required by the unified installer / PetaLinux build process,
# plus git/make/sudo for the build workflow and libpython3-dev for cocotb
# (installed via pip below -- there's no python3-cocotb apt package on
# Ubuntu 20.04). Verilator is intentionally NOT included -- see
# docker/README.md, "Testing" section.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    xterm \
    autoconf \
    libtool \
    texinfo \
    zlib1g-dev \
    gcc-multilib \
    build-essential \
    libncurses5-dev \
    libtinfo5 \
    git \
    make \
    sudo \
    ca-certificates \
    locales \
    chrpath \
    socat \
    tofrodos \
    iproute2 \
    unzip \
    tar \
    diffstat \
    cpio \
    rsync \
    file \
    gawk \
    device-tree-compiler \
    python3 \
    python3-pip \
    libpython3-dev \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Non-root build user -- PetaLinux refuses to run as root.
RUN groupadd -g ${BUILD_GID} builder \
    && useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
RUN pip3 install --user cocotb cocotb_coverage

WORKDIR /workspace

COPY --chown=builder:builder entrypoint.sh /home/builder/entrypoint.sh
RUN sudo chmod +x /home/builder/entrypoint.sh

ENTRYPOINT ["/home/builder/entrypoint.sh"]
CMD ["/bin/bash"]
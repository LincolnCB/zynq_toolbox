# ---------------------------------------------------------------------------
# zynq_toolbox cocotb/Verilator runner
#
# Fully self-contained -- unlike Vivado/PetaLinux, cocotb and Verilator are
# small enough to bake directly into the image rather than living in a
# separate tools volume. No Xilinx tools, no big volume, no license concerns.
# Rebuild this image to bump the cocotb or Verilator version (see
# VERILATOR_REF below).
# ---------------------------------------------------------------------------

FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_UID=1000
ARG BUILD_GID=1000

# Pin the Verilator tag to build. Ubuntu 20.04's packaged verilator (4.028)
# is too old for cocotb (needs 4.106+). Bump this and rebuild the image to
# upgrade -- see https://verilator.org for release tags.
ARG VERILATOR_REF=stable

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    make \
    build-essential \
    help2man \
    perl \
    flex \
    bison \
    ccache \
    libgoogle-perftools-dev \
    numactl \
    perl-doc \
    libfl2 \
    libfl-dev \
    zlibc \
    zlib1g \
    autoconf \
    python3 \
    python3-pip \
    libpython3-dev \
    ca-certificates \
    locales \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

RUN groupadd -g ${BUILD_GID} builder \
    && useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash builder

# Build Verilator from source, baked into the image (root-installed, so it
# persists across container recreation -- unlike the ad hoc VM-build
# approach in docker_install.md, we don't need a separate persistent volume
# here since a full image rebuild is cheap and reproducible).
WORKDIR /tmp/verilator
RUN git clone https://github.com/verilator/verilator . \
    && git checkout ${VERILATOR_REF} \
    && autoconf \
    && ./configure \
    && make -j"$(nproc)" \
    && make install \
    && cd / && rm -rf /tmp/verilator

USER builder
RUN pip3 install --user cocotb cocotb_coverage

WORKDIR /workspace

COPY --chown=builder:builder entrypoint-cocotb.sh /home/builder/entrypoint.sh
RUN chmod +x /home/builder/entrypoint.sh

ENTRYPOINT ["/home/builder/entrypoint.sh"]
CMD ["/bin/bash"]

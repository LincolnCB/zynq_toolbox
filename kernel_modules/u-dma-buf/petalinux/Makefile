# SPDX-License-Identifier: GPL-2.0 OR MIT
# Copyright (C) 2015-2023 Ichiro Kawazome

#
# Out of kernel tree variables
#
obj-m  += u-dma-buf.o
CONFIG_U_DMA_BUF                     ?= m
CONFIG_U_DMA_BUF_DEBUG               ?= y
CONFIG_U_DMA_BUF_QUIRK_MMAP          ?= y
CONFIG_U_DMA_BUF_IN_KERNEL_FUNCTIONS ?= y
CONFIG_U_DMA_BUF_IOCTL               ?= y
CONFIG_U_DMA_BUF_EXPORT              ?= y

CONFIG_OPTIONS := CONFIG_U_DMA_BUF=$(CONFIG_U_DMA_BUF)
CONFIG_OPTIONS += U_DMA_BUF_CONFIG=1
ifeq ($(CONFIG_U_DMA_BUF_DEBUG), y)
CONFIG_OPTIONS += U_DMA_BUF_DEBUG=1
else
CONFIG_OPTIONS += U_DMA_BUF_DEBUG=0
endif
ifeq ($(CONFIG_U_DMA_BUF_QUIRK_MMAP), y)
CONFIG_OPTIONS += U_DMA_BUF_QUIRK_MMAP=1
else
CONFIG_OPTIONS += U_DMA_BUF_QUIRK_MMAP=0
endif
ifeq ($(CONFIG_U_DMA_BUF_IN_KERNEL_FUNCTIONS), y)
CONFIG_OPTIONS += U_DMA_BUF_IN_KERNEL_FUNCTIONS=1
else
CONFIG_OPTIONS += U_DMA_BUF_IN_KERNEL_FUNCTIONS=0
endif
ifeq ($(CONFIG_U_DMA_BUF_IOCTL), y)
CONFIG_OPTIONS += U_DMA_BUF_IOCTL=2
else
CONFIG_OPTIONS += U_DMA_BUF_IOCTL=0
endif
ifeq ($(CONFIG_U_DMA_BUF_EXPORT), y)
CONFIG_OPTIONS += U_DMA_BUF_EXPORT=1
else
CONFIG_OPTIONS += U_DMA_BUF_EXPORT=0
endif

#
# Out of kernel tree rules
#
all:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) $(CONFIG_OPTIONS) modules

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) $(CONFIG_OPTIONS) modules_install

clean:
	rm -f *.o *~ core .depend .*.cmd *.ko *.mod.c
	rm -f Module.markers Module.symvers modules.order
	rm -rf .tmp_versions Modules.symvers


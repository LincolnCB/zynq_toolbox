# Makefile for the cma kernel module
# This module is built from cma.c
obj-m += cma.o

# Nothing needs to be changed from here
PWD := $(shell pwd)
default:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
// SPDX-License-Identifier: GPL-2.0
/*
 * pl-reg -- non-root, mmap-only access to PL AXI register windows, bound
 *           AUTOMATICALLY to the device-tree nodes PetaLinux already generates.
 *
 * This is the whole point of ex05: give userspace the SAME direct, full-speed
 * access to the PL registers that /dev/mem gives -- but without root, scoped to
 * only these registers instead of all of physical memory, AND without writing a
 * single line of device tree by hand.
 *
 * ---------------------------------------------------------------------------
 * How the binding works (the key idea of this example)
 * ---------------------------------------------------------------------------
 * PetaLinux's device-tree generator (DTG) already emits one node for every IP
 * in the Vivado address map. For ex05's two cores it produces, with no input
 * from us:
 *
 *   axi_cfg_register@40000000 { compatible = "xlnx,axi-cfg-register-1.0";
 *                               reg = <0x40000000 0x1000>; };
 *   axi_sts_register@40100000 { compatible = "xlnx,axi-sts-register-1.0";
 *                               reg = <0x40100000 0x1000>; };
 *
 * and it preserves each core's Vivado INSTANCE name as the DTS label on its
 * node ("cfg:" / "sts:" below), which the device-tree compiler records in the
 * /__symbols__ node as a label -> path map:
 *
 *   cfg: axi_cfg_register@40000000 { ... };   sts: axi_sts_register@40100000 { ... };
 *   __symbols__ { cfg = "/pl-bus/axi_cfg_register@40000000";
 *                 sts = "/pl-bus/axi_sts_register@40100000"; };
 *
 * The DTG mangles the VLNV (vendor:library:name:version) into the compatible as
 * "xlnx,<name-with-dashes>-<version>" -- note the vendor is always rewritten to
 * "xlnx", so the string encodes core NAME + VERSION only.
 *
 * This driver binds by listing those auto-generated compatibles in its
 * of_match_table (see pl_reg_of_match below). Because each core is a separate
 * node, the kernel calls probe() once PER node, so we get ONE device (and one
 * /dev entry) per register window -- e.g. /dev/cfg and /dev/sts. There is no
 * hand-written device_tree.dtsi anywhere in this project.
 *
 * ---------------------------------------------------------------------------
 * Naming: /dev/<instance>, so userspace never sees an address
 * ---------------------------------------------------------------------------
 * A compatible identifies a core TYPE, not a specific instance, so it cannot by
 * itself tell one instance from another (the node NAME is the shared core name,
 * "axi_cfg_register", too). The instance identity survives as the DTS label,
 * recorded in /__symbols__. In probe() we reverse-look up this node's label
 * (pl_reg_instance_name) and name the misc device after it, giving /dev/cfg and
 * /dev/sts. The base address is used only internally, and even that is read
 * from the node's own reg -- single-sourced from the block design.
 *
 * Fail-loud property: if a core's VLNV name or version changes, its
 * auto-compatible changes too, this driver stops matching, probe() never runs,
 * and /dev/<alias> is never created -- so userspace open() fails with ENOENT
 * instead of silently poking the wrong register.
 *
 * ---------------------------------------------------------------------------
 * How userspace uses it (see software/reg-driver)
 * ---------------------------------------------------------------------------
 *     cfd = open("/dev/cfg", O_RDWR);                 // no root needed
 *     cfg = mmap(NULL, len, PROT_RW, MAP_SHARED, cfd, 0);
 *     sfd = open("/dev/sts", O_RDWR);
 *     sts = mmap(NULL, len, PROT_RW, MAP_SHARED, sfd, 0);
 *     cfg[0] = a; cfg[1] = b;                          // plain pointer writes
 *     result = sts[0];                                 // plain pointer read
 *
 * Same open/mmap/deref pattern as a /dev/mem program (compare reg-mem.c). Two
 * things change, and only two:
 *
 *   1. You open a named device, not /dev/mem. The node is created 0666 (see
 *      DEV_MODE below), so an ordinary user can open it. /dev/mem can never be
 *      handed out this way because it exposes all of physical memory.
 *
 *      Why 0666 and not 0660: the misc core creates the node owned root:root and
 *      can only set its *mode*, not its *group*. Assigning a friendlier group is
 *      a udev job, and this rootfs has no udev. With 0660 the node stays
 *      root:root and a non-root user (who is not in the root group) is denied.
 *      0666 makes it world-accessible, which is the only udev-free way to reach
 *      it without root. Scope is still limited to just these registers.
 *
 *   2. There are no physical addresses in userspace, and each device maps a
 *      single window at mmap offset 0. Userspace opens the register by NAME
 *      (/dev/cfg), never by address -- if the block moves in the hardware
 *      design, the auto-generated node moves with it and userspace is unchanged.
 *
 * Why it is exactly as fast as /dev/mem: mmap() installs page-table entries
 * that point straight at the register's physical pages (io_remap_pfn_range,
 * non-cached). After that, every access is a single load/store instruction --
 * no syscall per access. It is the same mechanism /dev/mem uses, so the speed
 * is identical. The kernel is only involved once, at mmap() time.
 *
 * This driver is intentionally mmap-only. There is no read()/write()/ioctl()
 * path, because those would be a syscall per access -- the slow thing we are
 * trying to get away from. Keeping it to just mmap keeps the driver small and
 * the "how do I port my /dev/mem code" story a one-line change.
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <linux/io.h>
#include <linux/slab.h>
#include <linux/string.h>

#define DRIVER_NAME "pl-reg"
#define DEV_MODE    0666               /* world-accessible: no root, no udev */

/* One of these per bound node. The auto-generated node carries a single reg
 * window, so we track a single window here (not an array). The /dev name is
 * copied in because misc.name must outlive probe(). */
struct pl_reg_dev {
	phys_addr_t       phys;
	resource_size_t   size;
	struct miscdevice misc;
	char              name[48];
};

static int pl_reg_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct miscdevice *misc = file->private_data;
	struct pl_reg_dev *pr = container_of(misc, struct pl_reg_dev, misc);
	unsigned long len = vma->vm_end - vma->vm_start;

	/* Each device exposes exactly one window, mapped at offset 0. */
	if (vma->vm_pgoff != 0)
		return -EINVAL;

	/* Never let a mapping run past the end of the window. */
	if (len > PAGE_ALIGN(pr->size))
		return -EINVAL;

	/* Registers are MMIO: the mapping must be non-cached. */
	vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

	/* Map the window's physical pages straight into the process. After this
	 * returns, userspace accesses the registers with no further syscalls. */
	return io_remap_pfn_range(vma, vma->vm_start,
				  pr->phys >> PAGE_SHIFT,
				  len, vma->vm_page_prot);
}

static const struct file_operations pl_reg_fops = {
	.owner = THIS_MODULE,
	.mmap  = pl_reg_mmap,
};

/* Scan the /aliases- or /__symbols__-style directory at `dir_path` for the
 * property whose value (a node path) resolves back to `np`, and return that
 * property's name. Returns NULL if none matches, in which case the caller
 * falls back to the bare node name. */
static const char *pl_reg_lookup_name(const char *dir_path, struct device_node *np)
{
	struct device_node *dir;
	struct property *pp;
	const char *result = NULL;

	dir = of_find_node_by_path(dir_path);
	if (!dir)
		return NULL;

	/* Every property here maps a name -> a node path. The property whose
	 * path resolves back to our node gives us that node's instance name. */
	for_each_property_of_node(dir, pp) {
		struct device_node *target;

		/* Skip the housekeeping properties the kernel adds. */
		if (!strcmp(pp->name, "name") || !strcmp(pp->name, "phandle"))
			continue;

		target = of_find_node_by_path(pp->value);
		if (target == np)
			result = pp->name;
		of_node_put(target);
		if (result)
			break;
	}

	of_node_put(dir);
	return result;
}

/* Recover this node's Vivado instance name (e.g. "cfg" / "sts") so the /dev
 * entry can be named after it rather than after the shared core name
 * ("axi_cfg_register", which every instance of that core would share).
 *
 * Where the instance name actually lives (verified against a real 2024.2 DTB):
 * PetaLinux does NOT put PL cores in /aliases -- that node only carries the
 * standard serialN / spiN entries. Instead the instance name is emitted as the
 * DTS *label* on the node ("cfg: axi_cfg_register@40000000"), and the device-
 * tree compiler (run with -@) preserves every label in a /__symbols__ node as a
 * label -> path map. So we check /aliases first (the conventional place, in
 * case a core is ever given a real alias) and then /__symbols__, where the
 * Vivado instance labels actually are. */
static const char *pl_reg_instance_name(struct device_node *np)
{
	const char *name;

	name = pl_reg_lookup_name("/aliases", np);
	if (!name)
		name = pl_reg_lookup_name("/__symbols__", np);
	return name;
}

static int pl_reg_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct pl_reg_dev *pr;
	struct resource *res;
	const char *inst, *compat = NULL;
	int ret;

	pr = devm_kzalloc(dev, sizeof(*pr), GFP_KERNEL);
	if (!pr)
		return -ENOMEM;

	/* Auto-generated nodes carry a single reg range and NO reg-names, so we
	 * fetch the window by index (0) rather than by name. */
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res) {
		dev_err(dev, "no MEM resource in node\n");
		return -ENODEV;
	}

	/* Claim the window. This is the thing /dev/mem cannot do: the driver now
	 * *owns* these registers, so two drivers can't fight over them. (It does
	 * not lock out /dev/mem unless the kernel has CONFIG_IO_STRICT_DEVMEM.) */
	if (!devm_request_mem_region(dev, res->start, resource_size(res),
				     DRIVER_NAME)) {
		dev_err(dev, "region %pa already in use\n", &res->start);
		return -EBUSY;
	}

	pr->phys = res->start;
	pr->size = resource_size(res);

	/* Name the /dev node after the Vivado instance name (recovered from the
	 * DT symbols/aliases), so userspace opens /dev/cfg or /dev/sts and never
	 * touches an address. Fall back to the bare node name if this node
	 * somehow has no label. */
	inst = pl_reg_instance_name(dev->of_node);
	strscpy(pr->name, inst ? inst : dev->of_node->name, sizeof(pr->name));

	pr->misc.minor = MISC_DYNAMIC_MINOR;
	pr->misc.name  = pr->name;
	pr->misc.fops  = &pl_reg_fops;
	pr->misc.mode  = DEV_MODE;   /* world-rw node: non-root access, no udev */

	ret = misc_register(&pr->misc);
	if (ret) {
		dev_err(dev, "misc_register failed: %d\n", ret);
		return ret;
	}

	platform_set_drvdata(pdev, pr);
	of_property_read_string(dev->of_node, "compatible", &compat);
	dev_info(dev,
		 "/dev/%s ready (mode %#o): %pa size 0x%llx, compatible \"%s\"%s\n",
		 pr->name, DEV_MODE, &pr->phys,
		 (unsigned long long)pr->size, compat ? compat : "?",
		 inst ? "" : " (no DT label; used node name)");
	return 0;
}

static int pl_reg_remove(struct platform_device *pdev)
{
	struct pl_reg_dev *pr = platform_get_drvdata(pdev);

	misc_deregister(&pr->misc);
	return 0;
}

/* Bind to the compatibles PetaLinux's DTG auto-generates for ex05's two cores.
 * These are "xlnx,<vlnv-name-dashed>-<version>" -- the vendor part of the VLNV
 * (here pavel-demin) is always rewritten to "xlnx" by the generator. Add a line
 * here for any additional core type you want pl-reg to expose. */
static const struct of_device_id pl_reg_of_match[] = {
	{ .compatible = "xlnx,axi-cfg-register-1.0" },
	{ .compatible = "xlnx,axi-sts-register-1.0" },
	{ /* sentinel */ },
};
MODULE_DEVICE_TABLE(of, pl_reg_of_match);

static struct platform_driver pl_reg_driver = {
	.driver = {
		.name           = DRIVER_NAME,
		.of_match_table = pl_reg_of_match,
	},
	.probe  = pl_reg_probe,
	.remove = pl_reg_remove,
};

module_platform_driver(pl_reg_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Zynq Toolbox");
MODULE_DESCRIPTION("Non-root, mmap-only access to PL register windows, bound to PetaLinux auto-nodes (ex05)");

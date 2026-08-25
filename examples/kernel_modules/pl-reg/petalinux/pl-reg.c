// SPDX-License-Identifier: GPL-2.0
//
// pl-reg -- non-root, mmap-only access to a PL AXI register window (ex03).
//
// Gives userspace the same direct, full-speed register access as /dev/mem, but
// without root and scoped to a single core's registers instead of all physical
// memory.
//
// Binding: PetaLinux's device-tree generator emits one node per AXI core, with
// an auto-generated compatible of the form "xlnx,<core-name-dashed>-<version>"
// (it always rewrites the VLNV vendor to "xlnx"). This driver lists those
// compatibles in its of_match_table, so the kernel binds it once per node --
// one device, and one /dev entry, per register window, with no hand-written
// device tree. If a core's name or version changes its compatible changes too,
// the driver stops matching, and a stale mapping fails at open() instead of
// silently poking the wrong register.
//
// Naming: each /dev entry is named after the core's Vivado instance (e.g.
// /dev/cfg, /dev/sts), recovered from the node's DTS label, so userspace opens
// a register by name and never hard-codes an address. The base address is read
// from the node's own reg -- single-sourced from the block design.
//
// mmap-only on purpose: mmap points the process's page tables straight at the
// register pages, so every access afterward is a plain load/store with no
// syscall -- the same mechanism and speed as /dev/mem. A read()/write() path
// would cost a syscall per access, so it's deliberately left out.
//
// The node is created world-accessible (0666, see DEV_MODE): the misc core can
// set the node's mode but not its group, and this rootfs has no udev to fix up
// ownership, so 0666 is the only udev-free way to allow non-root access. Scope
// is still just this one register window. The userspace side is
// software/reg-driver.

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
#define DEV_MODE    0666               // world-accessible: no root, no udev

// One of these per bound node. The auto-generated node carries a single reg
// window, so we track a single window here (not an array). The /dev name is
// copied in because misc.name must outlive probe().
struct pl_reg_dev {
	phys_addr_t       phys;
	resource_size_t   size;
	struct miscdevice misc;
	char              name[48];
};

// Map the register window into the calling process at mmap offset 0
static int pl_reg_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct miscdevice *misc = file->private_data;
	struct pl_reg_dev *pr = container_of(misc, struct pl_reg_dev, misc);
	unsigned long len = vma->vm_end - vma->vm_start;

	// Each device exposes exactly one window, mapped at offset 0
	if (vma->vm_pgoff != 0)
		return -EINVAL;

	// Never let a mapping run past the end of the window
	if (len > PAGE_ALIGN(pr->size))
		return -EINVAL;

	// Registers are MMIO: the mapping must be non-cached
	vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

	// Map the window's physical pages straight into the process. After this
	// returns, userspace accesses the registers with no further syscalls.
	return io_remap_pfn_range(vma, vma->vm_start,
				  pr->phys >> PAGE_SHIFT,
				  len, vma->vm_page_prot);
}

static const struct file_operations pl_reg_fops = {
	.owner = THIS_MODULE,
	.mmap  = pl_reg_mmap,
};

// In a name -> node-path directory (/aliases or /__symbols__), find the entry
// pointing back at `np` and return its name (NULL if there's no match).
static const char *pl_reg_lookup_name(const char *dir_path, struct device_node *np)
{
	struct device_node *dir;
	struct property *pp;
	const char *result = NULL;

	dir = of_find_node_by_path(dir_path);
	if (!dir)
		return NULL;

	for_each_property_of_node(dir, pp) {
		struct device_node *target;

		// Skip the housekeeping properties the kernel adds
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

// Recover this node's Vivado instance label (e.g. "cfg" / "sts") so /dev can be
// named after it instead of the shared core name. PetaLinux emits the instance
// name as the node's DTS label, which the compiler records in /__symbols__;
// /aliases is checked first for the rare case a real alias exists.
static const char *pl_reg_instance_name(struct device_node *np)
{
	const char *name;

	name = pl_reg_lookup_name("/aliases", np);
	if (!name)
		name = pl_reg_lookup_name("/__symbols__", np);
	return name;
}

// One bound node -> one /dev/<instance> register window
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

	// One reg window per node, fetched by index
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res) {
		dev_err(dev, "no MEM resource in node\n");
		return -ENODEV;
	}

	// Claim the window so nothing else can grab these registers (this doesn't
	// lock out /dev/mem unless CONFIG_IO_STRICT_DEVMEM is set)
	if (!devm_request_mem_region(dev, res->start, resource_size(res),
				     DRIVER_NAME)) {
		dev_err(dev, "region %pa already in use\n", &res->start);
		return -EBUSY;
	}

	pr->phys = res->start;
	pr->size = resource_size(res);

	// Name /dev after the instance label; fall back to the node name
	inst = pl_reg_instance_name(dev->of_node);
	strscpy(pr->name, inst ? inst : dev->of_node->name, sizeof(pr->name));

	pr->misc.minor = MISC_DYNAMIC_MINOR;
	pr->misc.name  = pr->name;
	pr->misc.fops  = &pl_reg_fops;
	pr->misc.mode  = DEV_MODE;   // world-rw node: non-root access, no udev

	// Publish the /dev entry
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

// Bind to the compatibles PetaLinux auto-generates for ex03's cores, of the
// form "xlnx,<core-name-dashed>-<version>" (the generator always rewrites the
// vendor to "xlnx"). Add a line here for any other core you want to expose.
static const struct of_device_id pl_reg_of_match[] = {
	{ .compatible = "xlnx,axi-cfg-register-1.0" },
	{ .compatible = "xlnx,axi-sts-register-1.0" },
	// ex05: the project's device_tree.dtsi retags the MCDMA control window with
	// this private compatible so no in-kernel driver claims it, letting pl-reg
	// bind it and publish /dev/mcdma
	{ .compatible = "zynq-toolbox,mcdma-userspace" },
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
MODULE_DESCRIPTION("Non-root, mmap-only access to PL register windows, bound to PetaLinux auto-nodes (ex03)");

// SPDX-License-Identifier: GPL-2.0
/*
 * simple-reg -- non-root, mmap-only access to AXI register windows.
 *
 * This is the whole point of ex05: give userspace the SAME direct, full-speed
 * access to the PL registers that /dev/mem gives -- but without root, and
 * scoped to only these registers instead of all of physical memory.
 *
 * How userspace uses it (see software/reg-test):
 *
 *     fd  = open("/dev/simple-reg", O_RDWR);        // no root needed
 *     cfg = mmap(NULL, len, PROT_RW, MAP_SHARED, fd, 0);              // region 0
 *     sts = mmap(NULL, len, PROT_RW, MAP_SHARED, fd, getpagesize());  // region 1
 *     cfg[0] = a; cfg[1] = b;                        // plain pointer writes
 *     result = sts[0];                               // plain pointer read
 *
 * That is the exact same open/mmap/deref pattern as a /dev/mem program. Two
 * things change, and only two:
 *
 *   1. You open a named device, not /dev/mem. The node is created 0660 (see
 *      DEV_MODE below), so an ordinary user can open it. /dev/mem can never be
 *      handed out this way because it exposes all of physical memory.
 *
 *   2. The mmap offset is a small driver-defined *region selector*, not a raw
 *      physical address. Region 0 is "cfg", region 1 is "sts" (offset N*PAGE).
 *      Userspace never names 0x40000000 anywhere -- if the block moves in the
 *      hardware design, the device tree moves with it and userspace is
 *      unchanged.
 *
 * Why it is exactly as fast as /dev/mem: mmap() installs page-table entries
 * that point straight at the register's physical pages (io_remap_pfn_range,
 * non-cached). After that, every access is a single load/store instruction --
 * no syscall per access. It is the same mechanism /dev/mem uses, so the speed
 * is identical. The kernel is only involved once, at mmap() time.
 *
 * The two regions are deliberately NOT required to be adjacent: each is mapped
 * independently by its selector, so this scales to registers scattered across
 * the address map (as the Rev D Shim's really are).
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

#define DRIVER_NAME "simple-reg"
#define DEV_NAME    "simple-reg"       /* -> /dev/simple-reg */
#define DEV_MODE    0660               /* group-accessible: no root, no udev */

/* The device tree names the register windows. We bind to them by name (not by
 * index) so a reordering in the DT can never silently swap them. The order
 * here defines the mmap-offset selector: region 0 = "cfg", region 1 = "sts". */
static const char *const region_names[] = { "cfg", "sts" };
#define NUM_REGIONS ARRAY_SIZE(region_names)

struct simple_reg_region {
	phys_addr_t     phys;
	resource_size_t size;
};

struct simple_reg_dev {
	struct simple_reg_region regions[NUM_REGIONS];
	struct miscdevice        misc;
};

static int simple_reg_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct miscdevice *misc = file->private_data;
	struct simple_reg_dev *sr =
		container_of(misc, struct simple_reg_dev, misc);
	const struct simple_reg_region *r;
	unsigned long index = vma->vm_pgoff;              /* selector, in pages */
	unsigned long len   = vma->vm_end - vma->vm_start;

	/* The mmap offset selects which region to map. */
	if (index >= NUM_REGIONS)
		return -EINVAL;
	r = &sr->regions[index];

	/* Never let a mapping run past the end of its region. */
	if (len > PAGE_ALIGN(r->size))
		return -EINVAL;

	/* Registers are MMIO: the mapping must be non-cached. */
	vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

	/* Map the region's physical pages straight into the process. After this
	 * returns, userspace accesses the registers with no further syscalls. */
	return io_remap_pfn_range(vma, vma->vm_start,
				  r->phys >> PAGE_SHIFT,
				  len, vma->vm_page_prot);
}

static const struct file_operations simple_reg_fops = {
	.owner = THIS_MODULE,
	.mmap  = simple_reg_mmap,
};

static int simple_reg_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct simple_reg_dev *sr;
	int i, ret;

	sr = devm_kzalloc(dev, sizeof(*sr), GFP_KERNEL);
	if (!sr)
		return -ENOMEM;

	for (i = 0; i < NUM_REGIONS; i++) {
		struct resource *res;

		res = platform_get_resource_byname(pdev, IORESOURCE_MEM,
						   region_names[i]);
		if (!res) {
			dev_err(dev, "missing reg region \"%s\"\n",
				region_names[i]);
			return -ENODEV;
		}

		/* Claim the window. This is the thing /dev/mem cannot do: the
		 * driver now *owns* these registers, so two drivers can't fight
		 * over them. (It does not lock out /dev/mem unless the kernel
		 * was built with CONFIG_IO_STRICT_DEVMEM.) */
		if (!devm_request_mem_region(dev, res->start,
					     resource_size(res),
					     region_names[i])) {
			dev_err(dev, "region \"%s\" (%pa) already in use\n",
				region_names[i], &res->start);
			return -EBUSY;
		}

		sr->regions[i].phys = res->start;
		sr->regions[i].size = resource_size(res);
		dev_info(dev, "region %d \"%s\": %pa size 0x%llx (mmap offset 0x%lx)\n",
			 i, region_names[i], &res->start,
			 (unsigned long long)resource_size(res),
			 (unsigned long)i * PAGE_SIZE);
	}

	sr->misc.minor = MISC_DYNAMIC_MINOR;
	sr->misc.name  = DEV_NAME;
	sr->misc.fops  = &simple_reg_fops;
	sr->misc.mode  = DEV_MODE;   /* the node comes up non-root, no udev rule */

	ret = misc_register(&sr->misc);
	if (ret) {
		dev_err(dev, "misc_register failed: %d\n", ret);
		return ret;
	}

	platform_set_drvdata(pdev, sr);
	dev_info(dev, "/dev/%s ready (mode %#o), %zu regions\n",
		 DEV_NAME, DEV_MODE, NUM_REGIONS);
	return 0;
}

static int simple_reg_remove(struct platform_device *pdev)
{
	struct simple_reg_dev *sr = platform_get_drvdata(pdev);

	misc_deregister(&sr->misc);
	return 0;
}

static const struct of_device_id simple_reg_of_match[] = {
	{ .compatible = "zynq-toolbox,simple-reg" },
	{ /* sentinel */ },
};
MODULE_DEVICE_TABLE(of, simple_reg_of_match);

static struct platform_driver simple_reg_driver = {
	.driver = {
		.name           = DRIVER_NAME,
		.of_match_table = simple_reg_of_match,
	},
	.probe  = simple_reg_probe,
	.remove = simple_reg_remove,
};

module_platform_driver(simple_reg_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Zynq Toolbox");
MODULE_DESCRIPTION("Non-root, mmap-only access to AXI register windows (ex05)");

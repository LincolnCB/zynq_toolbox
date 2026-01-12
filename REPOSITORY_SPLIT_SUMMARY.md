# Repository Split Complete! 🎉

## Summary

Successfully split the `rev_d_shim` repository into `zynq_toolbox` (main) with 9 submodules.

## New Structure

### Main Repository
- **Name:** `zynq_toolbox` (formerly `rev_d_shim`)
- **GitHub:** https://github.com/LincolnCB/zynq_toolbox
- **Local Path:** `/home/lcb-virt/zynq_toolbox`

### Submodules (9 total)

**Projects (2):**
- `projects/rev_d_shim` → https://github.com/LincolnCB/rev_d_shim
- `projects/shim_controller_v0` → https://github.com/LincolnCB/shim_controller_v0

**Boards (4):**
- `boards/sdrlab_122_16` → https://github.com/LincolnCB/sdrlab_122_16
- `boards/snickerdoodle_black` → https://github.com/LincolnCB/snickerdoodle_black
- `boards/stemlab_125_14` → https://github.com/LincolnCB/stemlab_125_14
- `boards/zybo_z7_10` → https://github.com/LincolnCB/zybo_z7_10

**Custom Cores (2):**
- `custom_cores/open-mri` → https://github.com/LincolnCB/open-mri-cores
- `custom_cores/pavel-demin` → https://github.com/LincolnCB/pavel-demin-cores

**Kernel Modules (1):**
- `kernel_modules/u-dma-buf` → https://github.com/LincolnCB/u-dma-buf

### Kept in Main Repository
- Example projects: `ex01_basics` through `ex05_dma`
- Build scripts and tooling
- `custom_cores/base` (for later manual splitting)
- `kernel_modules/dummy-kmod` (for later manual splitting)

---

## Common Git Submodule Commands

### Cloning the Repository
```bash
# Clone with all submodules
git clone --recursive git@github.com:LincolnCB/zynq_toolbox.git

# Or if already cloned, initialize submodules
cd zynq_toolbox
git submodule update --init --recursive
```

### Checking Submodule Status
```bash
git submodule status
```

### Updating All Submodules
```bash
# Pull latest changes from all submodule remotes
git submodule update --remote --merge

# Then commit the updated submodule references
git add .
git commit -m "Update submodules"
git push
```

### Working in a Submodule
```bash
# Navigate to submodule
cd projects/rev_d_shim

# Make changes
# ... edit files ...

# Commit changes
git add .
git commit -m "Your changes"
git push

# Return to main repo and update submodule reference
cd ../..
git add projects/rev_d_shim
git commit -m "Update rev_d_shim submodule"
git push
```

### Pulling Changes (including submodules)
```bash
git pull
git submodule update --init --recursive
```

---

## What Was Preserved

✅ **Full git history** for each submodule
✅ **All files and commits** from the original folders
✅ **.gitignore** copied to each submodule

---

## Next Steps (Optional)

1. **Add README.md** to each submodule repository for documentation
2. **Set up branch protection** on GitHub for important repos
3. **Configure CI/CD** if needed for individual submodules
4. **Later:** Split `custom_cores/base` and `kernel_modules/dummy-kmod` when ready

---

## Backup Information

Split repositories are available in: `/home/lcb-virt/repo_split_workspace/`

These contain the local git repositories before they were pushed to GitHub.
You can delete this folder once you're confident everything is working correctly.

---

## Important Notes

- Submodules point to specific commits, not branches
- When updating a submodule, you need to commit the update in the main repo
- Team members will need to use `--recursive` when cloning
- Use `git submodule update --init --recursive` after pulling changes

---

Generated: January 9, 2026

# Xiaomi Dagu 4.19 build

## Device baseline

- Device: `dagu` (`22081281AC`)
- Android: 14
- Running kernel: `4.19.157-perf-gb2d363e0cc8d`
- Compiler reported by the device: Android clang `10.0.7`
- Kernel source: MiCode `dagu-s-oss`, pinned to `2f4aa27840d3b7bb61454de676f044fa0dd942c1`
- Defconfig: `dagu_user_defconfig`

The running configuration enables `CONFIG_KALLSYMS_ALL`, loadable modules,
`CONFIG_MODVERSIONS`, KGSL, and debug info. It uses no LTO. The stock
configuration does not expose `register_kprobe` or `unregister_kprobe`, while
this driver's symbol resolver requires kprobes. The build script enables
`CONFIG_KPROBES` in the custom kernel and builds the module against the same
output tree so its symbol CRCs and vermagic match that Image.

## Symbols checked through ADB

Present on the connected device:

`kallsyms_lookup_name`, `aarch64_insn_patch_text`, `release_pages`,
`input_class`, `kgsl_process_init_sysfs`, `sysfs_create_group`, `do_exit`,
`__arm64_sys_sendto`, `__sys_sendto`, `breakpoint_handler`,
`watchpoint_handler`, `finish_task_switch`, `bp_on_reg`, `wp_on_reg`,
`perf_bp_event`, `syscall_trace_exit`, `__switch_to`, `__arm64_sys_ioctl`,
`do_mem_abort`, `brk_handler`, and `filldir64`.

Not present under the names used by the driver:

`register_kprobe`, `unregister_kprobe`, `kgsl_process_init_debugfs`,
`call_step_hook`, `do_el0_svc`, `__se_sys_ioctl`, and the CFI slowpath names.

The missing feature-specific hook names mean those optional operations need a
4.19-specific implementation before use. They do not participate in module
initialization. Module, process, kernel-thread, and KGSL hiding calls are
disabled in `lsdriver/lsdriver.c`.

## Build

GitHub Actions runs `.github/workflows/build-dagu.yml` on pushes to `main` or
from the Actions `workflow_dispatch` button. For a Linux host, the equivalent
entry point is:

```bash
KERNEL_DIR=/path/to/dagu-kernel \
TOOLCHAIN_DIR=/path/to/proton-clang \
bash scripts/build_dagu.sh
```

Artifacts are written to `dist/dagu` and include the kernel Image, compressed
Image, DTB/DTBO files, `.config`, `System.map`, `Module.symvers`, build metadata,
and `lsdriver.ko`.

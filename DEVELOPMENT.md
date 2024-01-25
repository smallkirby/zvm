# Development Notes

## Boot Protocol

ZVM uses **32-bit boot protocol**.
It transits to 32-bit protected-mode kernel code [entry point](https://github.com/torvalds/linux/blob/v4.16/arch/x86/boot/compressed/head_64.S)
with *zero-page* set up
and with paging disabled.

## References

- [bobuhiro11/gokvm](https://github.com/bobuhiro11/gokvm): VMM backed by KVM in Go.
- [The Linux/x86 Boot Protocol](https://www.kernel.org/doc/html/v5.6/x86/boot.html): Kernel in-tree documentation on the boot protocol.
- [The Definitive KVM API Documentation](https://docs.kernel.org/virt/kvm/api.html#): KVM API documentation.
- [KVM HOST IN A FEW LINES OF CODE](https://zserge.com/posts/kvm/): Minimal KVM host in C that can partially boot Linux.
- [linux-insides](https://0xax.gitbooks.io/linux-insides/content/): Detailed guide to the Linux kernel.

## Tips

```bash
# Extract boot_params from bzImage
dd if=<bzImage> of=<out.bin> bs=1 skip=$((0)) count=$((0x1000))
```

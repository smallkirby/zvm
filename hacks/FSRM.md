# Workaround for FSRM Alternative Instruction Error

## Introduction

In the kernel boot process (`start_kernel()@/init/main.c`),
it checks CPU-specific bugs and opportunities to use alternative instructions for better performance.

`alternative_instructions()@arch/x86/kernel/alternative.c` is called
to check the available alternative instructions for the current CPU.
In this function, it calls `apply_alternatives(__alt_instructions, __alt_instructions_end)`.
The arguments are the list of old and new instructions.
These lists seems constructed by linker while the build-time (though I'm not sure).

For example, `/arch/x86/lib/memmove_64.S` contains the following code:

```asm
	ALTERNATIVE "cmp $0x20, %rdx; jb 1f", "", X86_FEATURE_FSRM
```

This means that if the CPU supports `X86_FEATURE_FSRM` (Fast Short REP MOVSB),
the instruction `cmp $0x20, %rdx; jb 1f` is replaced with empty string.
These are recorded in `__alt_instructions` and `__alt_instructions_end`,
and passed to `apply_alternatives()`.

This function applies the binary patch to the loaded kernel image.
Before applying the patch, it checks the current CPU supports the alternative instructions
by checking the CPU features.

CPU features are stored in `struct cpuinfo_x86 boot_cpu_data`.
The data is obtained by `cpuid` instruction in `get_cpu_cap()@/arch/x86/kernel/cpu/common.c`.
The capability is a bitfield consisting of 32-bit x 21 entries (at least on my environment).
`__alt_instructions` contains `cpuid` feature
and the alternative instruction is applied only if the feature is set.
The check is performed by `boot_cpu_has(feature)` macro.
In short, it just does:

```c
boot_cpu_data.x86_capability[feature >> 5] & (1 << (feature & 0x1F))
```

## Problem

When the kernel is applying the patches,
it unintentionally exited with `KVM_SHUTDOWN` exit reason.
The last log was below:

```
[   44.106505][    T0] SMP alternatives: feat: 18*32+4, old: (__memmove+0x1b/0x1af (ffffffff81395fdb) len: 10), repl: (ffffffff81b8a831, len: 0)
```

The log means that:

- The CPU supports `X86_FEATURE_FSRM` (Fast Short REP MOVSB).
- The old instruction is `__memmove+0x1b/0x1af (ffffffff81395fdb) len: 10`.
- The new instruction is `ffffffff81b8a831, len: 0`.

FSRM feature flag is defined at `arch/x86/include/asm/cpufeature.h`:

```c
#define X86_FEATURE_FSRM		(18*32+ 4) /* Fast Short Rep Mov */
```

Register information at the time of exit is below:

```
RAX: 0xFFFFFFFF81803CCB
RBX: 0x0000000000000004
RCX: 0x000000007E7FC338
RDX: 0xFFFFFFFFFFFECCA2
RSI: 0xFFFFFFFF81816FE7
RDI: 0xFFFFFFFF81816FEB
RSP: 0xFFFFFFFF81803B88
RBP: 0xFFFFFFFF81803CC7
R8:  0x0000000000000000
R9:  0x0000000000000000
R10: 0x0000000000000000
R11: 0x0000000000000000
R12: 0xFFFFFFFF81803CC9
R13: 0x000000007E7FC339
R14: 0xFFFFFFFF81754B36
R15: 0x0000000000000000
RIP: 0xFFFFFFFF8139600B
RFLAGS: 0x0000000000010282
```

RIP refers to:

```gef
0xffffffff81396007 <memmove+71>:     mov    r9,QWORD PTR [rsi+0x10]
0xffffffff8139600b <memmove+75>:     mov    r8,QWORD PTR [rsi+0x18]
0xffffffff8139600f <memmove+79>:     lea    rsi,[rsi+0x20]
```

I guess that `RSI` is not aligned to 0x8 bytes.
Is it the reason of the error?
I'm not sure.
Possibly it is because the kernel is trying to patch `memmove` function
while the function is being executed as the log indicates.
Anyway, ZVM needs to workaround this issue
by disabling the FSRM feature.

## Workaround

To disable the FSRM feature, you have to set CPUID properly.
The feature bit is stored in 4th bit of `x86_capability[18]` as its definition shows.
In `get_cpu_cap()`, the 18th entry is set to `EDX` register
of the result of `CPUID` function `0x7`.

```c
enum cpuid_leafs
{
	CPUID_1_EDX		= 0,
	CPUID_8000_0001_EDX,
	CPUID_8086_0001_EDX,
	CPUID_LNX_1,
	CPUID_1_ECX,
	CPUID_C000_0001_EDX,
	CPUID_8000_0001_ECX,
	CPUID_LNX_2,
	CPUID_LNX_3,
	CPUID_7_0_EBX,
	CPUID_D_1_EAX,
	CPUID_LNX_4,
	CPUID_7_1_EAX,
	CPUID_8000_0008_EBX,
	CPUID_6_EAX,
	CPUID_8000_000A_EDX,
	CPUID_7_ECX,
	CPUID_8000_0007_EBX,
	CPUID_7_EDX, // = 18
	CPUID_8000_001F_EAX,
};

cpuid_count(0x00000007, 0, &eax, &ebx, &ecx, &edx);
c->x86_capability[CPUID_7_0_EBX] = ebx;
c->x86_capability[CPUID_7_ECX] = ecx;
c->x86_capability[CPUID_7_EDX] = edx;
```

Therefore, we added the following code to the CPUID initialization code:

```zig
fn init_cpuid(self: *@This()) !void {
		var cpuid = try kvm.system.get_supported_cpuid(self.kvm_fd);

		for (0..cpuid.nent) |i| {
				var entry = &cpuid.entries[i];
				switch (entry.function) {
						...
						7 => {
								entry.edx &= ~(@as(u32, 1) << 4); // X86_FEATURE_FSRM
						},
						...
				}
		}
		...
}
```

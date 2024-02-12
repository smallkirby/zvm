//! CPUID feature flags.

/// List of CPUID functions set to EAX on CPUID instruction.
pub const functions = enum(u32) {
    pub const FEATURE_INFORMATION = 0x0000_0001;
    pub const STRUCTURE_EXTENDED_FEATURE_FLAGS = 0x0000_0007;
    pub const KVM_CPUID_SIGNATURE = 0x4000_0000;
};

/// CPUID Feature Flags bitfield.
/// This value is returned by the CPUID instruction in the ECX when EAX is 1.
pub const CpuidFeatureFlagEcx = packed struct(u32) {
    sse3: bool = false,
    pclmulqdq: bool = false,
    dtes64: bool = false,
    monitor: bool = false,
    ds_cpl: bool = false,
    vmx: bool = false,
    smx: bool = false,
    eist: bool = false,
    tm2: bool = false,
    ssse3: bool = false,
    cnxt_id: bool = false,
    sdbg: bool = false,
    fma: bool = false,
    cmpxchg16b: bool = false,
    xtpr: bool = false,
    pdcm: bool = false,
    _reserved_0: bool = false,
    pcid: bool = false,
    dca: bool = false,
    sse4_1: bool = false,
    sse4_2: bool = false,
    x2apic: bool = false,
    movbe: bool = false,
    popcnt: bool = false,
    tsc_deadline: bool = false,
    aesni: bool = false,
    xsave: bool = false,
    osxsave: bool = false,
    avx: bool = false,
    f16c: bool = false,
    rdrand: bool = false,
    hypervisor: bool = false,
};

/// CPUID Feature Flags bitfield.
/// This value is returned by the CPUID instruction in the EDX when EAX is 1.
pub const CpuidFeatureFlagEdx = packed struct(u32) {
    fpu: bool = false,
    vme: bool = false,
    de: bool = false,
    pse: bool = false,
    tsc: bool = false,
    msr: bool = false,
    pae: bool = false,
    mce: bool = false,
    cx8: bool = false,
    apic: bool = false,
    _reserved_0: bool = false,
    sep: bool = false,
    mtrr: bool = false,
    pge: bool = false,
    mca: bool = false,
    cmov: bool = false,
    pat: bool = false,
    pse36: bool = false,
    psn: bool = false,
    clfsh: bool = false,
    _reserved_1: bool = false,
    ds: bool = false,
    acpi: bool = false,
    mmx: bool = false,
    fxsr: bool = false,
    sse: bool = false,
    sse2: bool = false,
    ss: bool = false,
    htt: bool = false,
    tm: bool = false,
    _reserved_2: bool = false,
    pbe: bool = false,
};

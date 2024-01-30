# ZVM: experimental toy VMM in Zig backed by KVM

![Lint](https://github.com/smallkirby/zvm/actions/workflows/fmt.yml/badge.svg)
![Unit Tests](https://img.shields.io/travis/com/smallkirby/zvm?style=flat&logo=travis&label=Unit%20Tests)

<div style="text-align: center;">
  <img src="/docs/zvm.gif" alt="ZVM" style="border-radius: 15px;" />
</div>

**ZVM** is an experimental, educational, and just-for-fun minimal toy VMM.
ZVM is entirely written in Zig language.
ZVM is accelerated by KVM and Intel VT-x hardware virtualization extension.
The implementation is minimal,
but can boot Linux kernel v6.2.

## Status

Under development... 🚧

| Subject | Status |
|---|---|
| `initram`/`initrd` support | 🌞 |
| Boot `init` process | 🌞 |
| Configurable memory size | 🌞 |
| Keyboard interraction | 🌞 |
| Networking support (`virtio-net`) | 🌧 |
| Support multi cores | ⛈ |
| Switchable logging | ⛅ |
| Not depend on external libc | 🌞 |
| CI | ⛅ |

## Run

You need `bzImage` kernel image that is configured properly.
The example config is available at [/assets/config.linux](/assets/.config.linux).
You also need `initrd`/`initram` image that contains your `init` process.

```bash
zig build run -- --kernel=<bzImage> --initrd=<initrd/initram>
```

It will automatically install dependency (ZVM uses ZON as a package manager),
build ZVM, and run it.
You can see all available options by `zig build run -- --help`:

```bash
$ zig build run -- --help
    -h, --help
            Display this help and exit.
    -k, --kernel <str>
            Kenel bzImage path.
    -i, --initrd <str>
            initramfs or initrd path.
    -m, --memory <str>
            Memory size. (eg. 100MB, 1G, 2000B)
```

You can change the log level by editing `std_options` variable in [/src/main.zig](/src/main.zig).
Available log levels are `.debug`, `.info`, `.warn`, and `.err`.

## Tests

You possibly need root privilege to run tests depending on the capabilities you have.

```bash
zig build test --summary all
```

## Supported Platforms

- Intel x64 with VT-x enabled
- Host OS: Any modern version of Linux
- Guest OS: Linux v6.2
- Zig v0.11.0
  - It might work on later versions until Zig introduces breaking changes. But it would happen soon, Zig is still not a mature language at all...

## Notes

- [DEVELOPMENT.md](/DEVELOPMENT.md) contains some notes that might help develop VMM.
- [/hacks](/hacks) contains some pitfalls and hacks that I encountered during development.

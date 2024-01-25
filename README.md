# ZVM: experimental toy VMM in Zig backed by KVM

![Lint](https://github.com/smallkirby/zvm/actions/workflows/fmt.yml/badge.svg)

## Status

Under development... 🚧

| Subject | Status |
|---|---|
| `initram` support | 🌧 |
| `initrd` support | 🌧 |
| Boot `init` process | ☁️ |
| Variable memory size | 🌧 |
| Keyboard interruction | 🌧 |
| Networking support (`virtio-net`) | 🌧 |
| Support multi cores | ⛈ |
| Switchable logging | 🌧 |
| Not depend on libc | ☁️ |
| CI | 🌧 |

## Tests

```bash
zig build test --summary all
```

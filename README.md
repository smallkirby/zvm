# ZVM: experimental toy VMM backed by KVM written in Zig

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

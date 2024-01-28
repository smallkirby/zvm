# ZVM: experimental toy VMM in Zig backed by KVM

![Lint](https://github.com/smallkirby/zvm/actions/workflows/fmt.yml/badge.svg)
![Unit Tests](https://img.shields.io/travis/com/smallkirby/zvm?style=flat&logo=travis&label=Unit%20Tests)

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
| Switchable logging | 🌧 |
| Not depend on external libc | 🌞 |
| CI | ⛅ |

## Tests

```bash
zig build test --summary all
```

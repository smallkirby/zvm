# ZVM

## Tests

```bash
zig build test --summary all
```

## Tips

```bash
# Copy kernel header from bzImage
dd if=<bzImage> of=<out.bin> bs=1 skip=$((0)) count=$((0x1F1 + 128))
```

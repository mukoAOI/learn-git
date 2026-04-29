# mi-malloc

把 `mimalloc` 封装成 Zig 可依赖库，底层源码通过 `zig fetch` 拉取（当前使用 `v3.3.1`）。

## zig fetch 用法

先拉取本库（把 URL 换成你的仓库地址）：

```bash
zig fetch --save git+https://github.com/<you>/mi-malloc
```

本库会在解析依赖时自动拉取 `mimalloc`，你不需要手动再 `zig fetch` 一次 `mimalloc`。

然后在 `build.zig` 中：

```zig
const dep = b.dependency("mi_malloc", .{
    .target = target,
    .optimize = optimize,
});

const mimalloc_mod = dep.module("mimalloc");
const mimalloc_lib = dep.artifact("mimalloc");

exe.root_module.addImport("mimalloc", mimalloc_mod);
exe.linkLibrary(mimalloc_lib);
```

可选构建参数：

- `-Dbuild_static=true/false`：是否构建静态库（默认 `true`，产物名 `mimalloc`）
- `-Dbuild_shared=true/false`：是否构建动态库（默认 `true`，产物名 `mimalloc_shared`）
- `-Dmi_native_tune=true/false`：`ReleaseFast` 下默认 `true`（`-march=native`）；发通用二进制时请关。
- `-Dmi_opt_simd=true/false`：默认 `true`，相当于上游 `MI_OPT_SIMD=ON`（在 `__AVX2__` 等条件下走 SIMD 位图路径；**先前未开时 mimalloc 会明显偏慢**）。
- `-Dmi_lto=true/false`：`mimalloc` 库默认 `true`（full LTO）。
- `-Dmi_win_direct_tls=true/false`：Windows 默认 `true`（`MI_WIN_DIRECT_TLS`，快路径；若进程 `TlsAlloc` 很多可关）。

### 和 `std.heap.smp_allocator` 的差距

Zig 侧 `std.mem.Allocator` 每次分配要进一层 vtable 再调 C，极高频微分配时仍会慢于纯 Zig 的 smp。上限性能请直接调用 `mimalloc.malloc` / `mi_free`，或接受 smp 作为默认、部分热点换 mimalloc。

在 Zig 代码中：

```zig
const mimalloc = @import("mimalloc");

const p = mimalloc.malloc(128) orelse return error.OutOfMemory;
defer mimalloc.free(p);
```

或直接使用 `std.mem.Allocator` 接口：

```zig
const std = @import("std");
const mimalloc = @import("mimalloc");

var buf = try mimalloc.allocator.alloc(u8, 64);
defer mimalloc.allocator.free(buf);

buf = try mimalloc.allocator.realloc(buf, 128);
```

## Benchmark

对比 `mimalloc` 和 Zig 原生分配器：

```bash
zig build bench -Doptimize=ReleaseFast
```

当前 bench 会输出以下分配器的耗时：

- `mimalloc`
- `zig_smp_allocator`
- `zig_c_allocator`

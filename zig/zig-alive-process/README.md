# alive-progress for Zig

`alive_progress` 是一个 Zig 0.16 进度条库，目标是保留 Python
[`alive-progress`](https://github.com/rsalmei/alive-progress) 的动态显示体验，同时提供接近
`tqdm` 的简单使用方式。

这个实现是 Zig 版本的核心子集，不是 Python 项目的逐行翻译。当前支持：

- 已知总量、未知总量和手动百分比进度
- 动态刷新频率、平滑速率和 ETA
- spinner、最终 receipt、超出/不足总量提示
- 双缓冲渲染，减少整行清屏带来的闪烁
- 多种预设样式和自定义 bar 样式
- `range`、`forEach`、`withBar`、`untilDone` 等高层 API

暂未实现 Python 版的 print/log hook、Jupyter 支持、完整主题目录、grapheme 编译器、`alive_it`
和 pause API。

## 安装

项目以 Zig 包形式暴露模块名 `alive_progress`。

如果在同一个仓库中本地引用，可以在你的 `build.zig` 里添加依赖模块：

```zig
const alive = b.dependency("alive_progress", .{
    .target = target,
    .optimize = optimize,
});

const exe = b.addExecutable(.{
    .name = "my-app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "alive_progress", .module = alive.module("alive_progress") },
        },
    }),
});
```

在 `build.zig.zon` 中按你的项目布局配置依赖来源。开发时也可以直接运行本库自带示例：

```powershell
zig build example-basic
zig build example-unknown
zig build example-manual
zig build example-arrow
zig build example-easy
zig build example-until_done
```

## 基础用法

最直接的方式是创建一个 `AliveBar`，在工作循环中调用 `tick()`。

```zig
const std = @import("std");
const alive = @import("alive_progress");

pub fn main(init: std.process.Init) !void {
    const bar = try alive.AliveBar.create(init.gpa, init.io, 100, .{
        .title = "download",
        .length = 30,
        .refresh_ms = 160,
    });
    defer bar.destroy();

    for (0..100) |i| {
        _ = i;
        alive.platform.sleepNs(20 * std.time.ns_per_ms);
        bar.tick(1);
    }

    try bar.setText("done");
    try bar.finish();
}
```

`create()` 会在堆上创建进度条并立即启动刷新线程。使用完后调用 `destroy()`。如果你需要栈上分配，可以用
`init()`，赋值到稳定地址后再调用 `start()`，并确保之后不要移动该值。

## 高层 API

如果只是包装一个范围循环，可以使用 `range()`：

```zig
try alive.range(init.gpa, init.io, 50, .{
    .title = "range",
    .length = 28,
}, {}, runStep);

fn runStep(_: void, index: usize, bar: *alive.AliveBar) !void {
    if (index % 10 == 0) {
        var text_buf: [64]u8 = undefined;
        const text = try std.fmt.bufPrint(&text_buf, "step {d}", .{index});
        try bar.setText(text);
    }
    alive.platform.sleepNs(35 * std.time.ns_per_ms);
}
```

遍历切片或数组时可以使用 `forEach()`：

```zig
const jobs = [_][]const u8{ "download", "parse", "write" };

try alive.forEach(init.gpa, init.io, jobs[0..], .{
    .title = "jobs",
}, {}, runJob);

fn runJob(_: void, name: []const u8, _: usize, bar: *alive.AliveBar) !void {
    try bar.setText(name);
    alive.platform.sleepNs(200 * std.time.ns_per_ms);
}
```

如果想自己控制生命周期，但希望自动 `finish()`，可以使用 `withBar()`。

## 未知总量

当总量未知时，把 `total` 传成 `null`。进度条会显示滑动窗口样式，并继续显示计数、耗时和速率。

```zig
const bar = try alive.AliveBar.create(init.gpa, init.io, null, .{
    .title = "stream",
});
defer bar.destroy();

while (try readNextItem()) |_| {
    bar.tick(1);
}

try bar.finish();
```

如果是单个阻塞 API 调用，且 API 不提供进度回调，可以使用 `untilDone()`。它会在后台用 heartbeat 维持未知总量进度条。

```zig
try alive.untilDone(init.gpa, init.io, .{
    .title = "api",
    .length = 30,
}, 250, {}, callSlowApi);

fn callSlowApi(_: void, bar: *alive.AliveBar) !void {
    try bar.setText("connecting");
    alive.platform.sleepNs(800 * std.time.ns_per_ms);

    try bar.setText("waiting for remote service");
    alive.platform.sleepNs(1400 * std.time.ns_per_ms);
}
```

## 手动百分比

如果任务本身报告的是百分比或 fraction，启用 `.manual = true` 并调用 `setFraction()`：

```zig
const bar = try alive.AliveBar.create(init.gpa, init.io, 100, .{
    .title = "pipeline",
    .manual = true,
});
defer bar.destroy();

bar.setFraction(0.25);
try bar.setText("parse");

bar.setFraction(0.75);
try bar.setText("write");

bar.setFraction(1.0);
try bar.finish();
```

## 跳过项

`skip(delta)` 会推进当前位置，但不会把这些项计入吞吐量和 ETA。它适合缓存命中、已处理文件等场景。

```zig
bar.skip(10);
bar.tick(1);
```

## 样式

样式通过 `ProgressStyle` 配置。内置预设包括：

- `ProgressStyle.classic()`：默认 Unicode block 风格
- `ProgressStyle.square()`：方括号边框和简单 spinner
- `ProgressStyle.arrow()`：`=====>` 风格
- `ProgressStyle.naked()`：无边框、安静 spinner

示例：

```zig
const bar = try alive.AliveBar.create(init.gpa, init.io, 100, .{
    .title = "arrow",
    .style = alive.ProgressStyle.arrow(),
});
```

自定义 bar：

```zig
const custom_style = alive.ProgressStyle.custom(
    alive.BarSpec.fromPartsWithUnknown("#", "@", ".", "#", "."),
    "[",
    "]",
    &.{ "-", "\\", "|", "/" },
    "! ",
);

const bar = try alive.AliveBar.create(init.gpa, init.io, 100, .{
    .style = custom_style,
});
```

`BarSpec.fromParts(fill, tip, empty)` 会让未知总量模式复用 `fill` 和 `empty`。如果未知总量需要不同字符，使用
`BarSpec.fromPartsWithUnknown()`。

## 配置项

`Config` 常用字段：

- `length`：进度条宽度，默认 `40`
- `max_cols`：最大输出列宽，默认 `120`
- `style`：进度条样式，默认 `ProgressStyle.classic()`
- `refresh_ms`：最小刷新间隔，默认 `120`
- `force_tty`：强制开启或关闭 TTY 交互模式，默认自动检测
- `disable`：完全禁用输出
- `title`：进度条标题，最长 `max_title_len`
- `receipt`：结束时是否打印最终 receipt
- `manual`：启用手动百分比模式

为了贴近 Zig 的显式资源管理，`title` 和 `setText()` 使用 `AliveBar` 内部固定缓冲区，不会在每次更新时分配内存。
当前标题最长 `max_title_len`，右侧文本最长 `max_text_len`；超过长度会返回错误。

## 公开 API

主模块导出：

- `AliveBar`
- `Config`
- `ProgressStyle`
- `BarSpec`
- `BarParts`
- `max_title_len`
- `max_text_len`
- `max_frame_len`
- `withBar`
- `range`
- `forEach`
- `untilDone`
- 子模块：`progress`、`api`、`style`、`render`、`timing`、`terminal`、`platform`

常用 `AliveBar` 方法：

- `tick(delta)`：推进进度
- `skip(delta)`：推进但不计入速率
- `setFraction(frac)`：手动百分比模式下设置 `[0, 1]` 进度
- `setText(text)`：更新右侧提示文本
- `current()`：读取当前进度
- `elapsed()`：读取已耗时秒数
- `finish()`：停止刷新并打印最终 receipt
- `destroy()`：释放 `create()` 分配的实例

## 测试和开发

在 `zig/` 目录运行：

```powershell
zig build
zig build test
zig fmt build.zig build.zig.zon src/*.zig examples/*.zig
```

生成最终可执行文件时，建议用 Zig 的优化模式控制速度和体积：

```powershell
zig build example-arrow -Doptimize=ReleaseFast
zig build example-arrow -Doptimize=ReleaseSmall
```

`ReleaseFast` 更偏运行速度，`ReleaseSmall` 更偏二进制体积。库本身只暴露模块，实际是否打包进最终 exe 取决于你的应用引用了哪些 API。
本库的 `build.zig` 会在 Release 模式下设置 `unwind_tables = .none`，进一步减少生成物体积；Debug 模式保持默认，方便调试。

本库已经去掉独立 `main.zig` demo，可执行演示通过 `examples/` 下的 build steps 提供。作为依赖使用时，只需要导入
`alive_progress` 模块。

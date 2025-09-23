```shell
$ zig build --help

用法：/home/ci/deps/zig-linux-x86_64-0.14.0/zig build [步骤] [选项]

构建步骤：
  install (默认)            将构建产物复制到前缀路径
  uninstall                 从前缀路径移除构建产物

通用选项：
  -p, --prefix [路径]         安装文件的目录 (默认: zig-out)
  --prefix-lib-dir [路径]     安装库文件的目录
  --prefix-exe-dir [路径]     安装可执行文件的目录
  --prefix-include-dir [路径] 安装 C 头文件的目录

  --release[=模式]           请求发布模式，可指定优先优化模式：fast(快速), safe(安全), small(小巧)

  -fdarling,  -fno-darling    与系统安装的 Darling 集成，在 Linux 主机上运行 macOS 程序
                               (默认: 禁用)
  -fqemu,     -fno-qemu       与系统安装的 QEMU 集成，在 Linux 主机上运行非本机架构程序
                               (默认: 禁用)
  --glibc-runtimes [路径]     通过提供为多种非本机架构构建的 glibc 来增强 QEMU 集成，
                               允许运行链接了 glibc 的非本机程序。
  -frosetta,  -fno-rosetta    依赖 Rosetta 在 ARM64 macOS 主机上运行 x86_64 程序。
                               (默认: 禁用)
  -fwasmtime, -fno-wasmtime   与系统安装的 wasmtime 集成，运行 WASI 二进制文件。
                               (默认: 禁用)
  -fwine,     -fno-wine       与系统安装的 Wine 集成，在 Linux 主机上运行 Windows 程序。
                               (默认: 禁用)

  -h, --help                   打印此帮助信息并退出
  -l, --list-steps             打印可用的构建步骤
  --verbose                    在执行命令前打印它们
  --color [auto|off|on]        启用或禁用彩色错误信息
  --prominent-compile-errors   缓冲编译错误并在最后显示
  --summary [模式]             控制构建摘要的打印
    all                        完整打印构建摘要
    new                        省略缓存的步骤
    failures                   (默认) 仅打印失败的步骤
    none                       不打印构建摘要
  -j<N>                        限制并发作业数 (默认使用所有 CPU 核心)
  --maxrss <字节数>            限制内存使用量 (默认使用可用内存)
  --skip-oom-steps             跳过会超出 --maxrss 限制的步骤，而不是失败
  --fetch                      在获取完依赖树后退出
  --watch                      当源文件被修改时持续重新构建
  --fuzz                       持续搜索单元测试失败
  --debounce <毫秒>            检测到文件更改后，延迟指定毫秒再开始重新构建
     -fincremental             启用增量编译
  -fno-incremental            禁用增量编译

项目特定选项：
  -Dwindows=[布尔值]           以 Microsoft Windows 为目标系统

系统集成选项：
  --search-prefix [路径]       添加一个用于查找二进制文件、库、头文件的路径
  --sysroot [路径]             设置系统根目录 (通常为 /)
  --libc [文件]                提供一个指定 libc 路径的文件

  --system [包目录]            禁用包获取；启用所有集成
  -fsys=[名称]                 启用一个系统集成
  -fno-sys=[名称]              禁用一个系统集成

  可用的系统集成:               已启用:
  (无)                                        -

高级选项：
  -freference-trace[=数量]     每个编译错误显示多少行引用跟踪信息
  -fno-reference-trace         禁用引用跟踪
  -fallow-so-scripts           允许 .so 文件是 GNU ld 脚本
  -fno-allow-so-scripts        (默认) .so 文件必须是 ELF 文件
  --build-file [文件]          覆盖 build.zig 的路径
  --cache-dir [路径]           覆盖本地 Zig 缓存目录的路径
  --global-cache-dir [路径]    覆盖全局 Zig 缓存目录的路径
  --zig-lib-dir [参数]         覆盖 Zig 库目录的路径
  --build-runner [文件]        覆盖构建运行器的路径
  --seed [整数]                用于打乱依赖遍历顺序 (默认: 随机)
  --debug-log [范围]           启用编译器调试日志
  --debug-pkg-config           遇到未知的 pkg-config 标志时失败
  --debug-rt                   调试编译器运行时库
  --verbose-link               启用链接的编译器调试输出
  --verbose-air                启用 Zig AIR 的编译器调试输出
  --verbose-llvm-ir[=文件]     启用 LLVM IR 的编译器调试输出
  --verbose-llvm-bc=[文件]     启用 LLVM BC 的编译器调试输出
  --verbose-cimport            启用 C 导入的编译器调试输出
  --verbose-cc                 启用 C 编译的编译器调试输出
  --verbose-llvm-cpu-features  启用 LLVM CPU 特性检测的编译器调试输出
```


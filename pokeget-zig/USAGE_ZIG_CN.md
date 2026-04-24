# pokeget-zig 使用教程

这份文档介绍如何在当前仓库中使用 Zig 版本的 `pokeget`（可在终端渲染宝可梦 sprite）。

## 1. 环境准备

请先确认：

- 已安装 Zig（且 `zig` 命令可用）
- 已进入项目根目录（本仓库）

可选：

- 如果你也想对比 Rust 版本性能，需安装 Rust/Cargo

## 2. 准备 sprite 资源

Zig 版本运行时会读取：

- `data/pokesprite/pokemon-gen8/...`

如果你是刚克隆仓库，请先初始化子模块（如果项目使用了 submodule）：

```powershell
git submodule update --init --recursive
```

如果运行时报 `sprite file not found`，通常就是这一步没完成。

## 3. 构建 Zig 版本

### Debug 构建

```powershell
zig build
```

### Release 构建（推荐）

```powershell
zig build -Doptimize=ReleaseFast
```

默认构建产物（当前 `build.zig`）：

- `zig-out/pokeget-zig/pokeget-zig.exe`（Windows）
- `zig-out/pokeget-zig/data/...`（运行所需资源）

可自定义安装目录（推荐）：

```powershell
zig build -Doptimize=ReleaseFast -Dinstall-dir=release
```

此时产物在：

- `zig-out/release/pokeget-zig.exe`
- `zig-out/release/data/...`

## 4. 运行方式

### 方式 A：直接运行（推荐开发时）

```powershell
zig build run -- <pokemon...> [options]
```

示例：

```powershell
zig build run -- bulbasaur
zig build run -- bulbasaur pikachu random
```

### 方式 B：运行已构建二进制

```powershell
.\zig-out\pokeget-zig\pokeget-zig.exe <pokemon...> [options]
```

如果你使用了 `-Dinstall-dir=release`，则是：

```powershell
.\zig-out\release\pokeget-zig.exe <pokemon...> [options]
```

> 注意：当前程序**不支持子命令**，只有位置参数和选项。

## 4.1 二进制速查（可直接复制）

```powershell
# 构建到 zig-out/release
zig build -Doptimize=ReleaseFast -Dinstall-dir=release

# 查看帮助
.\zig-out\release\pokeget-zig.exe --help

# 基本用法（可多个）
.\zig-out\release\pokeget-zig.exe pikachu
.\zig-out\release\pokeget-zig.exe bulbasaur pikachu eevee

# 随机 / 图鉴号 / 地区
.\zig-out\release\pokeget-zig.exe random
.\zig-out\release\pokeget-zig.exe 25
.\zig-out\release\pokeget-zig.exe kanto

# 外观参数
.\zig-out\release\pokeget-zig.exe raichu --alolan --shiny
.\zig-out\release\pokeget-zig.exe charizard --mega-x
.\zig-out\release\pokeget-zig.exe typhlosion --hisui --noble
```

## 5. 参数说明

### 基础

- `<pokemon...>`：可传多个（名字、图鉴号、`random`、地区名）
- `--hide-name`：不输出名字行
- `-h, --help`：显示帮助

### 形态与外观

- `-f, --form <form>`：自定义形态后缀
- `-m, --mega`：mega
- `--mega-x`：mega-x
- `--mega-y`：mega-y
- `-a, --alolan`：alola
- `--gmax`：gmax
- `--hisui`：hisui
- `--galar`：galar
- `-n, --noble`：追加 `-noble`
- `--female`：雌性外观
- `-s, --shiny`：强制闪光

## 6. 常用示例

### 单只

```powershell
zig build run -- charizard
```

### 多只拼接

```powershell
zig build run -- bulbasaur pikachu eevee
```

### 随机

```powershell
zig build run -- random
```

### 地区随机

```powershell
zig build run -- kanto
zig build run -- johto
```

### 指定图鉴号

```powershell
zig build run -- 1 25 150
```

### 组合参数

```powershell
zig build run -- raichu --alolan --shiny
zig build run -- charizard --mega-x
zig build run -- typhlosion --hisui --noble
```

## 7. 输出与重定向

程序输出的是 ANSI 彩色字符图。  
如果你想保存文本：

```powershell
zig build run -- pikachu > out.txt
```

注意：不同终端对 ANSI 支持程度不同，建议使用支持 TrueColor 的现代终端。

## 8. 常见问题

### Q1：报错 `sprite file not found`

原因通常是 sprite 资源未就绪。  
处理：

1. 检查 `data/pokesprite/pokemon-gen8` 是否存在 png 文件
2. 重新执行 `git submodule update --init --recursive`

### Q2：报错“you must specify the pokemon you want to display”

你没有传 `<pokemon...>` 参数。  
例如改成：

```powershell
zig build run -- bulbasaur
```

### Q3：显示颜色不正常

请换一个支持 ANSI/TrueColor 的终端，或升级终端配置。

# ARM64 SoC SDK 工程目录规范与开发流程

> 技术路线基线
>
> | 项目 | 选型 |
> |---|---|
> | CPU | Cortex-A78AE / QEMU AArch64 (virt) |
> | 固件 | ARM Trusted Firmware (TF-A) v2.14 |
> | 安全系统 | OP-TEE |
> | Bootloader | U-Boot |
> | Kernel | Linux 6.1 / 6.9 |
> | 开发环境 | Windows 11 + WSL2 (Ubuntu 22.04/24.04) + VS Code |
> | 构建目标 | QEMU 虚拟平台，可扩展 RK3588 等 ARM64 SoC 板卡 |

## 0. 核心设计原则

本 SDK 的根本原则是**五分离**：

1. **上游源码**（`source/`）：保持上游 Git 仓库原样，只读管理，不直接在工作树上留脏改动。
2. **项目修改**（`patches/`）：所有业务性修改以 patch 文件形式保存，按组件、按 SoC/Board 分层。
3. **构建脚本**（`scripts/`）：拉代码、打补丁、编译、打包、烧录全部为可重复执行的脚本。
4. **配置**（`configs/`）：SoC、Board、Product 三级配置解耦，切换平台只改配置不动脚本。
5. **编译产物**（`out/`）：所有中间产物、最终镜像、日志集中输出，可整目录删除重建。

由此带来的收益：

- 更换 Kernel 6.1 → 6.9、TF-A v2.13 → v2.14 时，只需修改 manifest 与配置，**不需要重组目录**。
- 同一套 SDK 通过 `Product` 配置同时支持 QEMU 与 RK3588。
- 任何一台新开发机执行 `scripts/setup.sh` 即可复现完整构建环境。
- 所有定制修改有迹可循，可随时向上游 rebase。

---

## 1. SDK 完整目录树

```text
arm64-sdk/
├── manifest/               # 组件源码版本管理（repo manifest 或 git submodule 锁定）
│   ├── default.xml         # 默认 manifest：QEMU virt + Linux 6.9 + TF-A v2.14
│   ├── qemu-linux61.xml    # 变体：Linux 6.1
│   └── README.md           # manifest 语法与切换方法
│
├── configs/                # SoC / Board / Product 三级配置
│   ├── soc/
│   │   ├── qemu-virt.mk    # QEMU virt 平台参数（CPU 数、内存、UART 基址等）
│   │   └── rk3588.mk       # RK3588 平台参数（预留）
│   ├── board/
│   │   ├── qemu-a78ae.mk   # 板级：Cortex-A78AE 模拟配置
│   │   └── rk3588-evb.mk   # 板级：RK3588 EVB（预留）
│   ├── product/
│   │   ├── qemu_debug.mk   # 产品：QEMU 调试版（开启 GDB、日志、无签名）
│   │   └── qemu_release.mk # 产品：QEMU 发布版（预留安全启动）
│   └── kernel/
│       ├── qemu_defconfig  # Linux 6.9 QEMU 平台 defconfig 增量
│       └── fragments/      # Kconfig fragment：optee.cfg、debug.cfg、perfetto.cfg
│
├── source/                 # 上游源码（repo/submodule 管理，只读基线）
│   ├── arm-trusted-firmware/   # TF-A v2.14
│   ├── optee/
│   │   ├── optee_os/       # OP-TEE 核心
│   │   ├── optee_client/   # 非安全侧 client 库与 tee-supplicant
│   │   └── optee_examples/ # TA/CA 示例（实验用）
│   ├── u-boot/             # U-Boot
│   ├── linux/              # Linux 6.1 / 6.9（分支切换）
│   └── buildroot/          # RootFS 构建（可选，亦可 busybox 手工制作）
│
├── patches/                # 项目补丁（按组件/平台分层）
│   ├── tf-a/
│   │   ├── common/         # 平台无关补丁
│   │   └── qemu-virt/      # QEMU 平台补丁（0001-xxx.patch ...）
│   ├── optee/
│   ├── u-boot/
│   └── linux/
│       ├── common/
│       └── qemu-virt/
│
├── board/                  # 板级私有文件
│   ├── qemu-a78ae/
│   │   ├── dts/            # 板级 DTS 覆盖（kernel + TF-A FDT）
│   │   ├── rootfs/         # rootfs overlay（etc/init.d、fstab、网络配置）
│   │   └── scripts/        # 板级专属脚本（启动参数、镜像布局）
│   └── rk3588-evb/         # 预留
│
├── toolchains/             # 交叉编译工具链（不入版本库，脚本下载）
│   ├── aarch64-none-linux-gnu/      # A-profile 内核/uboot/tfa 工具链
│   └── aarch64-none-elf/            # OP-TEE OS / 裸机用（可选）
│
├── tools/                  # 构建与调试辅助工具（源码或预编译）
│   ├── fiptool/            # TF-A fiptool（也可由 TF-A 构建产出）
│   ├── u-boot-tools/       # mkimage
│   ├── devtools/           # 自研小工具（镜像签名、布局生成）
│   └── perfetto/           # trace_processor / perfetto 二进制（调试版）
│
├── scripts/                # 全流程脚本（本 SDK 的入口）
│   ├── envsetup.sh         # 环境变量与 lunch（选择 product）
│   ├── setup.sh            # 首次安装：依赖、工具链、repo init
│   ├── sync.sh             # 拉取/切换源码（manifest 驱动）
│   ├── patch.sh            # patch apply / unapply / check
│   ├── build_tf-a.sh
│   ├── build_optee.sh
│   ├── build_uboot.sh
│   ├── build_kernel.sh
│   ├── build_rootfs.sh
│   ├── build_all.sh        # 一键全量构建
│   ├── pack_image.sh       # 生成 FIP、组合启动镜像、生成 QEMU 启动盘
│   ├── run_qemu.sh         # 启动 QEMU（含 -s -S 调试参数开关）
│   └── lib/                # 脚本公共函数库（日志、错误处理、配置加载）
│
├── debug/                  # 调试资产
│   ├── gdb/
│   │   ├── tfa.gdb         # TF-A 各 BL 阶段符号加载脚本
│   │   ├── kernel.gdb      # vmlinux + lx-symbols 自动加载
│   │   └── optee.gdb
│   ├── qemu/
│   │   └── gdbstub.cfg     # QEMU gdbstub 端口与启动参数约定
│   ├── openocd/            # 实体板卡 JTAG（预留 RK3588）
│   └── trace/
│       ├── ftrace/         # 常用 ftrace 采集脚本
│       └── perfetto/       # perfetto 配置（调度、freq、irq）
│
├── docs/                   # 技术文档
│   ├── sdk-directory-spec.md   # 本文档
│   ├── bringup-qemu.md
│   ├── patch-workflow.md
│   └── debug-guide.md
│
├── downloads/              # 下载缓存（tarball、工具链，可重下，入 .gitignore）
│   ├── toolchains/
│   └── tarballs/
│
└── out/                    # 全部构建产物（按 product 隔离，入 .gitignore）
    ├── qemu_debug/
    │   ├── tf-a/           # bl1.bin bl2.bin bl31.bin fip.bin
    │   ├── optee/          # tee-pager_v2.bin 等
    │   ├── u-boot/         # u-boot.bin
    │   ├── kernel/         # Image、Image.gz、DTB、modules
    │   ├── rootfs/         # rootfs.cpio.gz / ext4
    │   ├── images/         # 最终交付镜像（flash.bin、QEMU 启动组合）
    │   └── logs/           # 每次构建的时间戳日志
    └── qemu_release/
```

### 1.1 各目录职责速查表

| 目录 | 职责 | 入版本库 | 修改频率 |
|---|---|---|---|
| `manifest/` | 锁定每个组件的仓库地址与 commit/tag | ✅ | 换版本时 |
| `configs/` | SoC/Board/Product/Kernel 配置 | ✅ | 新增平台时 |
| `source/` | 上游源码工作树 | 由 repo 管理 | 每日开发 |
| `patches/` | 项目补丁，唯一允许的"定制"存在形式 | ✅ | 每次定制修改 |
| `board/` | 板级 DTS、rootfs overlay、板级脚本 | ✅ | 板级开发 |
| `toolchains/` | 交叉工具链 | ❌（脚本下载） | 极少 |
| `tools/` | fiptool、mkimage、trace 工具 | ✅(脚本)/❌(二进制) | 较少 |
| `scripts/` | 全流程脚本 | ✅ | 持续完善 |
| `debug/` | GDB/trace/OpenOCD 配置 | ✅ | 调试需要时 |
| `docs/` | 文档 | ✅ | 持续 |
| `downloads/` | 下载缓存 | ❌ | — |
| `out/` | 编译产物 | ❌ | 每次构建 |

### 1.2 `.gitignore` 基线

```gitignore
source/
out/
downloads/
toolchains/*/
*.swp
.vscode/settings.json.local
```

---

## 2. SoC / Board / Product 三级配置划分

三级配置是本 SDK 支持多平台的关键。每一级只负责自己关心的变量，上层通过 `make -C sdk PRODUCT=qemu_debug` 或 `source scripts/envsetup.sh && lunch qemu_debug` 注入。

### 2.1 SoC 级（`configs/soc/<soc>.mk`）

描述芯片本身的能力，与具体板子无关：

```makefile
# configs/soc/qemu-virt.mk
SOC_NAME        := qemu-virt
ARCH            := arm64
CROSS_COMPILE   := aarch64-none-linux-gnu-
TFA_PLAT        := qemu
OPTEE_PLATFORM  := vexpress-qemu_virt
UBOOT_DEFCONFIG := qemu_arm64_defconfig
KERNEL_DEFCONFIG:= defconfig
CPU_CORES       := 4
DRAM_BASE       := 0x40000000
DRAM_SIZE       := 2G
UART_BASE       := 0x09000000
```

### 2.2 Board 级（`configs/board/<board>.mk`）

描述板卡对 SoC 的实例化：内存大小裁剪、外设、DTS、rootfs 类型：

```makefile
# configs/board/qemu-a78ae.mk
include configs/soc/qemu-virt.mk
BOARD_NAME      := qemu-a78ae
QEMU_MACHINE    := virt,gic-version=3,virtualization=on,secure=on
QEMU_CPU        := max   # QEMU virt 无 a78ae 专用 model，用 max 并打开所需扩展
DTS_OVERLAYS    := board/qemu-a78ae/dts
ROOTFS_TYPE     := cpio.gz        # 调试期用 initramfs，免块设备
KERNEL_FRAGMENTS:= optee.cfg debug.cfg
```

### 2.3 Product 级（`configs/product/<product>.mk`）

描述"这颗板子以什么形态交付"：调试开关、签名、镜像布局：

```makefile
# configs/product/qemu_debug.mk
include configs/board/qemu-a78ae.mk
PRODUCT_NAME    := qemu_debug
BUILD_VARIANT   := debug
TFA_BUILD       := debug          # TF-A DEBUG=1, LOG_LEVEL=50
ENABLE_GDBSERVER:= y
ENABLE_PERFETTO := y
SIGN_IMAGES     := n
```

**规则**：下层文件 include 上层，上层定义默认值，下层只覆盖差异。新增 RK3588 时，新增 `soc/rk3588.mk` + `board/rk3588-evb.mk` + `product/rk3588_debug.mk` 三个文件即可，**一行脚本都不用改**——因为脚本只消费最终展开后的变量。

### 2.4 环境注入

`scripts/envsetup.sh` 的核心逻辑：

```bash
# 用法: source scripts/envsetup.sh && lunch qemu_debug
lunch() {
    local product=$1
    [ -f "$SDK_ROOT/configs/product/$product.mk" ] || { echo "unknown product"; return 1; }
    export SDK_PRODUCT=$product
    export SDK_OUT=$SDK_ROOT/out/$product
    # 把 mk 配置转成 shell 环境（用 make 展开，避免重复解析逻辑）
    eval $(make -s -C "$SDK_ROOT/scripts/lib" -f expand.mk PRODUCT=$product printenv)
    echo "== SDK: $SDK_PRODUCT | out: $SDK_OUT =="
}
```

---

## 3. 多仓库管理：Manifest 与版本锁定

### 3.1 方案选型：Google repo vs 纯 shell

| 方案 | 优点 | 缺点 | 建议 |
|---|---|---|---|
| `repo` + manifest.xml | 业界标准（AOSP/OP-TEE 均用），多仓库分支/锁定成熟 | 需安装 repo 工具 | **推荐**，长期维护 |
| git submodule | 无额外工具 | 多仓库批量操作繁琐，patch 工作流不顺 | 仅组件 ≤3 个时 |
| 自研 shell 脚本 | 完全可控 | 重复造轮子 | 备选 |

本规范采用 **repo**。`manifest/default.xml` 示例：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote  name="tfa"    fetch="https://git.trustedfirmware.org/TF-A"/>
  <remote  name="optee"  fetch="https://github.com/OP-TEE"/>
  <remote  name="u-boot" fetch="https://source.denx.de/u-boot"/>
  <remote  name="kernel" fetch="https://git.kernel.org/pub/scm/linux/kernel/git/stable"/>
  <remote  name="build"  fetch="https://github.com/buildroot"/>

  <default remote="kernel" revision="master" sync-j="8"/>

  <project path="source/arm-trusted-firmware" name="arm-trusted-firmware.git"
           remote="tfa"    revision="refs/tags/v2.14.0"/>
  <project path="source/optee/optee_os"       name="optee_os.git"
           remote="optee"  revision="refs/tags/4.5.0"/>
  <project path="source/optee/optee_client"   name="optee_client.git"
           remote="optee"  revision="refs/tags/4.5.0"/>
  <project path="source/optee/optee_examples" name="optee_examples.git"
           remote="optee"  revision="refs/tags/4.5.0"/>
  <project path="source/u-boot"               name="u-boot.git"
           remote="u-boot" revision="refs/tags/v2025.01"/>
  <project path="source/linux"                name="linux.git"
           remote="kernel" revision="refs/tags/v6.9.12"/>
  <project path="source/buildroot"            name="buildroot.git"
           remote="build"  revision="refs/tags/2025.02"/>
</manifest>
```

### 3.2 版本锁定策略

- **开发期**：manifest 用 tag（如 `v6.9.12`）而非分支名，保证任何时间点 `repo sync` 结果一致。
- **发布期**：执行 `repo manifest -r -o manifest/frozen-<release>.xml`，把每个仓库固化到具体 commit SHA，作为发布快照。
- **升级组件**：如 TF-A v2.14.0 → v2.15，只改 manifest 中一行 revision，然后：

```bash
scripts/sync.sh                 # repo sync
scripts/patch.sh unapply linux tf-a optee u-boot   # 先撤旧 patch
scripts/patch.sh apply                              # 重打（冲突时人工 rebase）
scripts/build_all.sh
```

- **多版本并存**：Linux 6.1 与 6.9 通过不同 manifest 文件区分（`qemu-linux61.xml` / `default.xml`），`scripts/sync.sh -m qemu-linux61.xml` 切换。

> 注意：上游源码体积大，首次 sync 建议 shallow clone：在 manifest 的 `<default>` 加 `sync-j="8"`，并在 sync 脚本中使用 `repo sync --depth=1 --no-tags`（调试需要完整历史时去掉 depth）。

---

## 4. Patch 管理

### 4.1 目录与命名规范

```text
patches/<组件>/<层级>/NNNN-描述.patch
```

- 组件：`tf-a`、`optee`、`u-boot`、`linux`
- 层级：`common`（所有平台适用）→ `<soc/board>`（如 `qemu-virt`），apply 时按 common → 平台 的顺序打
- 编号：`0001-` 起，四位数字，**编号即应用顺序**
- 命名：`0001-qemu-virt-enable-optee-early-console.patch`（小写、连字符、能自解释）

每个补丁必须是 **git format-patch 格式**，带完整 commit message：

```text
From 3f8a1c2... Mon Sep 17 00:00:00 2001
Subject: [PATCH qemu-virt 1/2] plat/qemu: increase BL2 size for OP-TEE

Why: OP-TEE 4.5 的 tee-pager 超出默认 BL2 预留空间。
What: PLAT_QEMU_BL2_SIZE 0x1F000 -> 0x24000
Upstream: No（板级定制，不送上上游）
Risk: 低，仅影响 qemu 平台内存布局
Test: Lab2 通过，fip.bin 正常启动到 BL33
```

commit message 中 **Why/What/Upstream/Risk/Test** 五段是强制的——半年后你会感谢自己。

### 4.2 Patch 生命周期（generate → save → apply → unapply）

**生成**（在 source 工作树中开发完成后）：

```bash
cd source/linux
git add -A && git commit -m "..."
git format-patch -N            # 最近 N 个 commit 导出为 patch
mv 000*.patch $SDK_ROOT/patches/linux/qemu-virt/
```

**应用**（全新环境或 sync 之后）：

```bash
scripts/patch.sh apply              # 全部组件
scripts/patch.sh apply linux        # 仅 linux
```

`patch.sh` 内部实现要点（用 `git am`，失败回退 `patch -p1`）：

```bash
apply_series() {
    local repo=$1 dir=$2
    [ -d "$repo/.patched" ] && return 0          # 幂等：已打则跳过
    for p in $(ls "$dir"/common/*.patch "$dir/$BOARD"/*.patch 2>/dev/null); do
        git -C "$repo" am --3way "$p" || {
            echo "[FAIL] $p"; git -C "$repo" am --abort; exit 1; }
        echo "$p" >> "$repo/.patched"
    done
}
```

**撤销**（升级上游版本前）：

```bash
scripts/patch.sh unapply linux   # 按 .patched 记录逆序 git am 的反向操作（git reset）
```

**状态检查**：

```bash
scripts/patch.sh check     # 列出每个仓库：上游版本、已打 patch、工作树是否干净
```

### 4.3 纪律

1. `source/` 工作树上的**任何**长期修改都必须最终落到 `patches/`，禁止"裸改不进库"。
2. 一次性试验代码允许存在，但 `patch.sh check` 会报警（工作树脏）。
3. Patch 尽量小步：一个逻辑修改一个 patch，便于向上游 rebase 与回退。
4. 能送上上游的修复（generic bug）应单独标记 `Upstream: Yes`，并安排提交到上游 mailing list / Gerrit。

---

## 5. 构建流程：从拉源码到镜像打包

### 5.1 首次环境搭建（约 30–60 分钟）

```bash
# WSL2 Ubuntu 内
git clone <your-sdk-repo> arm64-sdk && cd arm64-sdk
./scripts/setup.sh          # 装依赖包、下载工具链、装 repo
source scripts/envsetup.sh
lunch qemu_debug
./scripts/sync.sh           # repo init + sync（拉全部上游源码）
./scripts/patch.sh apply    # 打全部项目补丁
```

`setup.sh` 安装的依赖清单（apt）：

```text
build-essential bc bison flex libssl-dev libncurses-dev device-tree-compiler
u-boot-tools cpio rsync python3-pyelftools python3-cryptography
qemu-system-arm gdb-multiarch ccache ninja-build
device-tree-compiler swig libgnutls28-dev uuid-dev
```

工具链下载：Arm 官方 `arm-gnu-toolchain-*-aarch64-none-linux-gnu.tar.xz` 解压到 `toolchains/`，URL 与校验和写在 `configs/toolchain.mk` 中。

### 5.2 全量构建

```bash
./scripts/build_all.sh        # 按依赖顺序构建并打包
```

等价于依次执行：

```bash
build_tf-a.sh      # ① 产出 bl1.bin bl2.bin bl31.bin fip.bin
build_optee.sh     # ② OP-TEE OS（依赖工具链；其产物被 TF-A 打包进 FIP）
build_uboot.sh     # ③ U-Boot（BL33）
build_kernel.sh    # ④ Image + DTB + modules
build_rootfs.sh    # ⑤ buildroot/busybox → rootfs.cpio.gz
pack_image.sh      # ⑥ 组装 QEMU 启动镜像
```

> 实际依赖顺序：OP-TEE 与 U-Boot 需在 TF-A 打 FIP 之前就绪，因此脚本内部顺序为 optee → u-boot → tf-a(FIP) → kernel → rootfs → pack。每个脚本可独立运行，日常迭代只跑受影响的环节。

### 5.3 各组件构建要点

**TF-A（`scripts/build_tf-a.sh`）**

```bash
make -C source/arm-trusted-firmware \
    PLAT=qemu ARCH=aarch64 \
    CROSS_COMPILE=aarch64-none-linux-gnu- \
    DEBUG=1 LOG_LEVEL=40 \
    BL33=$SDK_OUT/u-boot/u-boot.bin \
    BL32=$SDK_OUT/optee/tee-header_v2.bin \
    BL32_EXTRA1=$SDK_OUT/optee/tee-pager_v2.bin \
    BL32_EXTRA2=$SDK_OUT/optee/tee-pageable_v2.bin \
    SPD=opteed \
    QEMU_USE_GIC_DRIVER=QEMU_GICV3 \
    all fip
```

产物拷贝至 `out/<product>/tf-a/`，FIP（含 BL2/BL31/BL32/BL33）由 `fiptool` 生成。

**OP-TEE（`scripts/build_optee.sh`）**

```bash
make -C source/optee/optee_os \
    CROSS_COMPILE=aarch64-none-linux-gnu- \
    PLATFORM=vexpress-qemu_virt \
    CFG_ARM64_core=y DEBUG=1
```

**U-Boot（`scripts/build_uboot.sh`）**

```bash
make -C source/u-boot qemu_arm64_defconfig
make -C source/u-boot CROSS_COMPILE=aarch64-none-linux-gnu- -j$(nproc)
```

**Kernel（`scripts/build_kernel.sh`）**

```bash
cd source/linux
make defconfig
# 应用 config fragment（optee.cfg debug.cfg perfetto.cfg）
scripts/kconfig/merge_config.sh .config $SDK_ROOT/configs/kernel/fragments/*.cfg
make -j$(nproc) Image dtbs modules
```

**RootFS（`scripts/build_rootfs.sh`）**：调试期推荐 buildroot 产出 `rootfs.cpio.gz` 作 initramfs；叠加 `board/qemu-a78ae/rootfs/` 中的 overlay（init 脚本、网络、调试工具）。

**打包（`scripts/pack_image.sh`）**

QEMU virt 的启动组合较简单：TF-A 的 `flash.bin`（BL1+FIP 合成）+ kernel Image + DTB + initramfs，全部通过 QEMU 命令行装载，无需制作磁盘镜像。脚本把最终文件归拢到 `out/<product>/images/` 并写一份 `manifest.txt`（记录每个文件的来源 commit 与构建时间）。

### 5.4 构建日志

每次构建写 `out/<product>/logs/YYYYMMDD-HHMMSS-<component>.log`，脚本结束时统一打印耗时摘要，便于定位编译性能瓶颈（配合 ccache，全量重建约可压缩到 5–10 分钟）。

---

## 6. 修改代码 → Commit → 导出 Patch 的日常流程

以"给内核加一个调试打印"为例：

```bash
# 1. 确认基线干净
scripts/patch.sh check

# 2. 直接在工作树上改代码（VS Code Remote-WSL 打开 source/linux）
cd source/linux
vim drivers/char/random.c

# 3. 编译验证（内核单模块可 make M=drivers/char 增量）
scripts/build_kernel.sh
scripts/run_qemu.sh            # 确认效果

# 4. 提交并导出 patch
git add -A
git commit -m "random: add debug print for early entropy

Why: 定位 QEMU 下熵不足导致的 getrandom 阻塞。
What: ..."
git format-patch -1
mv 0001-random-add-debug-print.patch \
   $SDK_ROOT/patches/linux/qemu-virt/

# 5. 验证闭环：回到干净基线，重新打 patch 必须可复现
scripts/patch.sh unapply linux
scripts/patch.sh apply linux
git -C source/linux status     # 应与手工提交后完全一致
```

**红线**：`patches/` 是定制的唯一持久形态。任何"我先在 source 里改了但没导出"的状态，在下一次 `sync.sh` 后都会丢失。

---

## 7. QEMU 启动与调试

### 7.1 正常启动（`scripts/run_qemu.sh`）

```bash
qemu-system-aarch64 \
    -machine virt,gic-version=3,secure=on,virtualization=on \
    -cpu max -smp 4 -m 2G -nographic \
    -bios out/qemu_debug/tf-a/flash.bin \
    -kernel out/qemu_debug/kernel/Image \
    -dtb  out/qemu_debug/kernel/qemu-virt-a78ae.dtb \
    -initrd out/qemu_debug/rootfs/rootfs.cpio.gz \
    -append "console=ttyAMA0,115200 earlycon loglevel=8" \
    -serial mon:stdio \
    -netdev user,id=n0 -device virtio-net-device,netdev=n0
```

TF-A 启动链：`BL1(ROM) → BL2 → BL31(EL3 runtime) → BL32(OP-TEE) → BL33(U-Boot) → Linux`。

### 7.2 QEMU + GDB

`run_qemu.sh --debug` 附加 `-s -S`（GDB stub 开 1234 端口，CPU 停在复位处）：

**调试 TF-A**（`debug/gdb/tfa.gdb`）：

```gdb
target remote :1234
# BL1 在 ROM 地址，无符号重定位问题
add-symbol-file out/qemu_debug/tf-a/bl1/bl1.elf
# BL31 运行在 EL3，注意 QEMU 的 secure EL3 与当前异常级切换
add-symbol-file out/qemu_debug/tf-a/bl31/bl31.elf
hbreak bl31_main
continue
```

**调试 Kernel**（`debug/gdb/kernel.gdb`）：

```gdb
target remote :1234
add-symbol-file out/qemu_debug/kernel/vmlinux
lx-symbols        # 需内核开启 CONFIG_GDB_SCRIPTS，自动加载模块符号
hbreak start_kernel
continue
# 常用：lx-dmesg / lx-lsmod / lx-ps
```

要点：

- QEMU `-S` 让 CPU 停在入口，可断到 TF-A BL1 第一行——这是调启动链死机的唯一手段。
- 内核解压后会自 relocate，`hbreak`（硬件断点）比软断点可靠。
- OP-TEE 侧调试：先用 `CFG_TEE_CORE_LOG_LEVEL` 提日志等级，GDB 挂 `tee.elf` 时注意 secure world 地址空间与 non-secure 的切换（QEMU gdbstub 两者共用，需看当前 EL）。

### 7.3 串口日志规范

- 单一 UART（PL011 @0x9000000）贯穿全启动链：TF-A `console=ttyAMA0` 与内核 cmdline 保持一致，避免换口丢日志。
- 日志分级约定：TF-A `LOG_LEVEL=40`（INFO）用于 bringup，稳定后降到 20；内核 `loglevel=8` 仅调试版。
- `run_qemu.sh --log` 把串口输出 tee 到 `out/<product>/logs/console-<ts>.log`，每次启动留档，方便 diff 两次启动差异。

### 7.4 Kernel Trace（ftrace）

`debug/trace/ftrace/` 提供采集脚本，典型流程：

```bash
# 目标机（QEMU 内）
mount -t tracefs nodev /sys/kernel/tracing
cd /sys/kernel/tracing
echo function > current_tracer
echo '*scheduler*' > set_ftrace_filter
echo 1 > tracing_on; sleep 5; echo 0 > tracing_on
cat trace > /tmp/trace.txt        # 通过 9p/virtio 传回 host
```

内核需开 `CONFIG_FUNCTION_TRACER / CONFIG_FUNCTION_GRAPH_TRACER / CONFIG_DYNAMIC_FTRACE`（已在 `debug.cfg` fragment 中）。

### 7.5 Perfetto

发布版/性能分析版（`ENABLE_PERFETTO=y`）使用 perfetto：

1. host 侧从 `tools/perfetto/` 取 `perfetto` 与 `trace_processor`（预编译 Linux/x64 与 arm64）。
2. 目标侧用 `debug/trace/perfetto/sched.cfg`（调度+frequency+irq 全量 10s 窗口）：

```bash
perfetto --txt -c sched.cfg -o /data/misc/perfetto-traces/sched.pb
```

3. 拉取 trace 后用 https://ui.perfetto.dev 打开分析。
4. 首次 bringup 建议先抓 **sched_switch + cpu_frequency + irq**，三件套足以覆盖 80% 的启动慢/卡顿问题。

### 7.6 常见问题定位速查

| 现象 | 首选手段 | 常见原因 |
|---|---|---|
| 串口无任何输出 | GDB `-s -S` 断 BL1 | FIP 布局错 / `-bios` 指向错 |
| 停在 BL2 | TF-A LOG_LEVEL=50 + GDB | DRAM 参数、BL32 镜像格式 |
| OP-TEE panic | tee 日志等级 4 + GDB tee.elf | TZC 配置、内存重叠 |
| U-Boot 不加载 kernel | U-Boot 手动 `bdinfo`/`md` | Image 地址与 DTB 地址冲突 |
| kernel 早期死无日志 | `earlycon` + GDB hbreak start_kernel | DTB 与机器不匹配、console 参数错 |
| 启动后随机 hang | ftrace sched / perfetto | 中断风暴、GIC 配置 |
| getrandom 阻塞 | 内核熵日志 | virtio-rng 未启用 |

---

## 8. Lab 0 ~ Lab 7 实验任务与验收标准

> 目的：让团队按统一路径吃透整条启动链。每个 Lab 建议时长 0.5–2 天，验收以可复现的命令与日志为准。

### Lab 0：环境搭建
- **任务**：完成 `setup.sh` + `sync.sh` + `patch.sh apply` + `build_all.sh`，启动 QEMU 看到 shell。
- **验收**：在一台全新 WSL2 上从零执行，2 小时内复现；提交 `out/qemu_debug/logs/` 完整构建日志。

### Lab 1：启动链认知（TF-A）
- **任务**：把 TF-A LOG_LEVEL 调到 50（VERBOSE），梳理 BL1→BL2→BL31→BL32→BL33 各阶段的入口地址与交接参数；用 GDB 在 `bl31_main` 断点确认。
- **验收**：手绘（或文档）启动时序图一份；GDB 截图证明在 BL31 断住并能打印当前 EL。

### Lab 2：Patch 工作流
- **任务**：在 U-Boot 加一条 `sdkversion` 命令（打印 SDK 版本字符串），走完整"改代码→commit→format-patch→unapply→apply"闭环。
- **验收**：`patch.sh unapply u-boot && patch.sh apply u-boot` 后构建结果与手工版一致；patch 文件符合命名与 message 规范。

### Lab 3：OP-TEE 入门
- **任务**：编译并运行 `optee_examples/hello_world`（CA 调 TA）；修改 TA 使其返回当前 secure timer 值。
- **验收**：QEMU 内 `hello_world` 输出正确；TA 修改以 patch 形式入库 `patches/optee/`。

### Lab 4：Kernel 定制
- **任务**：给内核加一个字符设备驱动（misc device），实现 `read` 返回内核版本+构建时间；写用户态测试程序。
- **验收**：`cat /dev/sdk_demo` 输出正确；驱动代码以 patch 入库，rootfs overlay 包含测试程序。

### Lab 5：GDB 调试实战
- **任务**：人为在内核某 probe 函数引入空指针 bug，用 QEMU `-s -S` + GDB 定位到出错行；再用 `lx-dmesg` 复盘。
- **验收**：提交定位过程记录（断点设置、backtrace、寄存器），从复现到定位 ≤30 分钟。

### Lab 6：Trace 与性能
- **任务**：用 ftrace 抓内核启动期 function graph，找出启动耗时 Top5 的 initcall；用 perfetto 抓 10s 调度 trace，确认 4 核负载分布。
- **验收**：提交 trace 文件与 Top5 列表；perfetto UI 截图标注关键调度异常（如有）。

### Lab 7：镜像打包与发布
- **任务**：新建 product `qemu_release`（DEBUG=0、LOG_LEVEL=20、关闭调试 fragment），全量构建并生成发布镜像包（含 manifest.txt 记录每个组件 commit）。
- **验收**：发布镜像可启动且串口日志干净（无 debug 噪音）；`manifest.txt` 与 `repo manifest -r` 输出一致。

---

## 9. 扩展到 RK3588 等实体板卡的路径

1. **配置层**：新增 `configs/soc/rk3588.mk`（`TFA_PLAT=rk3588`、`OPTEE_PLATFORM=rockchip-rk3588` 或 rockchip 闭源 TEE 说明）、`configs/board/rk3588-evb.mk`、`configs/product/rk3588_debug.mk`。
2. **Manifest 层**：新增 `rk3588.xml`，TF-A/U-Boot/Kernel 切换为 Rockchip BSP fork（或 mainline + 补丁集），注明 vendor 仓库与 mainline 的差异策略。
3. **Patch 层**：新增 `patches/*/rk3588/` 层级，common 补丁保持复用。
4. **打包层**：`pack_image.sh` 按平台分支——RK3588 需要 `idbloader.img`（DDR 初始化 + SPL）、`u-boot.itb`、boot/ext4 分区镜像与 `rkdeveloptool` 烧录。
5. **调试层**：`debug/openocd/` 启用 RK3588 JTAG 配置；串口参数改 1500000 波特率。
6. **验收标准不变**：Lab 0–7 在 RK3588 上全部可重跑，只是 QEMU-specific 步骤换成实体板对应手段。

---

## 10. 附：脚本接口速查

| 命令 | 作用 |
|---|---|
| `source scripts/envsetup.sh && lunch <product>` | 选择产品并注入环境 |
| `scripts/setup.sh` | 首次安装依赖与工具链 |
| `scripts/sync.sh [-m manifest.xml]` | 拉取/切换源码版本 |
| `scripts/patch.sh apply\|unapply\|check [组件]` | 补丁管理 |
| `scripts/build_<component>.sh` | 单组件增量构建 |
| `scripts/build_all.sh` | 全量构建 |
| `scripts/pack_image.sh` | 生成启动镜像 |
| `scripts/run_qemu.sh [--debug] [--log]` | 启动 QEMU（可带 GDB stub / 日志） |

---

*文档版本：v1.0 · 适用基线：TF-A v2.14 / OP-TEE 4.5 / U-Boot v2025.01 / Linux 6.1 & 6.9*

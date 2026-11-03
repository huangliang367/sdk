# ATF、SCP 与 Linux 上下电流程：QEMU / FVP 学习与调试方案

## 1. 环境选择结论

建议采用两阶段路线：

1. **先用 QEMU `virt`**：学习 Linux PSCI、TF-A PSCI Runtime Service、CPU hotplug、CPU idle 和基本 suspend/resume。
2. **再用 Arm FVP + SCP-firmware**：学习 SCMI、SCP Power Domain，以及 AP 与 SCP 的协同电源管理。

如果能获取对应模型，优先考虑 **SGI-575 FVP** 做 SCP-firmware 实验。你已有的 QEMU + TF-A + OP-TEE 工程可直接作为第一阶段基础。不要因为暂时没有 FVP 而停止学习。

注意：QEMU `virt` 通常不等价于一套带独立 SCP 固件的真实 SoC。FVP 是否包含 SCP，取决于具体平台模型；不是所有 FVP 都支持完整 SCP 工作流。Cortex-A78 CPU FVP 也不等于 Cortex-A78AE，更不代表一定包含 SCP。最终还需要在目标 A78AE SoC 上核对真实电源域、寄存器和平台固件实现。

## 2. ATF、SCP、PSCI、SCMI 的关系

| 名称 | 主要职责 |
|---|---|
| TF-A / ATF | Arm Trusted Firmware，通常运行在 EL3，提供安全启动、异常级切换、PSCI 等固件服务 |
| SCP | System Control Processor，通常是 SoC 内独立管理处理器，负责电源、时钟、复位、性能等系统管理 |
| PSCI | Power State Coordination Interface，定义 CPU_ON、CPU_OFF、CPU_SUSPEND、SYSTEM_OFF 等标准电源管理接口 |
| SCMI | System Control and Management Interface，定义 AP 与系统控制固件之间的管理协议，如 Power、Clock、Performance、Reset |
| Linux | 根据调度、CPU hotplug、cpuidle、系统 suspend 等策略发起请求 |

关键区别：

- **PSCI 不等于 SCMI**：PSCI 是操作系统与 EL3 固件之间的标准接口；SCMI 是客户端与系统管理固件之间的管理协议。
- **ATF 不等于 SCP**：ATF 通常运行在 AP 的 EL3；SCP 通常运行在独立管理核上。
- 不同 SoC 的实现不同。TF-A 可能直接控制电源硬件，也可能通过 SCMI/MHU 请求 SCP，或者两者分工。不能假设所有平台都由 SCP 控制全部电源域。

## 3. 典型系统架构

```text
                    Application Processor (AP)
┌──────────────────────────────────────────────────────────────┐
│ Linux Kernel                                                  │
│  CPU hotplug / cpuidle / suspend                             │
│       │ PSCI                         │ SCMI                   │
└───────┼──────────────────────────────┼────────────────────────┘
        │ SMC                          │ Mailbox / Shared Memory
        ▼                              ▼
┌──────────────────────┐      ┌──────────────────────────────┐
│ TF-A BL31             │      │ SCMI Transport               │
│ PSCI Runtime Service  │      │ Mailbox / MHU / SMC 等       │
│ Platform PM callbacks │      └──────────────┬───────────────┘
└──────────┬───────────┘                     │
           │                                 ▼
           │                       ┌──────────────────────────┐
           │                       │ SCP Firmware             │
           │                       │ SCMI service              │
           │                       │ Power Domain / Clock      │
           │                       │ Reset / Performance       │
           │                       └────────────┬─────────────┘
           └──────────────────┬────────────────┘
                              ▼
                  SoC Power / Clock / Reset HW
```

这是概念架构，不代表所有平台都采用相同连接方式。某些平台 PSCI 完全由 TF-A 控制硬件；某些平台 Linux SCMI 请求由 SCP 处理；还有的平台由 TF-A 和 SCP 分工协作。

## 4. 四类上下电流程

### 4.1 CPU_ON：启动一个离线 CPU

```text
Linux CPU hotplug / SMP
    -> psci_cpu_on()
    -> SMC: PSCI_CPU_ON
    -> TF-A PSCI Runtime Service
    -> 参数、MPIDR、CPU 状态检查
    -> 平台回调 pwr_domain_on()
    -> 直接操作电源控制器，或请求 SCP 上电
    -> Power Domain / Clock / Reset 操作
    -> 释放 CPU reset
    -> TF-A warm / secondary entry
    -> Linux secondary CPU startup
```

调试重点：

- Linux 是否发起 `PSCI_CPU_ON`。
- SMC function ID、目标 CPU MPIDR、entry point 和 context 参数。
- TF-A 是否进入 PSCI CPU_ON handler。
- 平台 `pwr_domain_on()` 是否被调用。
- 若使用 SCP：SCMI/MHU 请求是否发出、SCP 是否收到、Power Domain 是否完成状态转换。
- CPU 是否释放 reset，是否进入 TF-A secondary entry，最后是否进入 Linux。

实际回调名称、同步/异步行为和调用顺序取决于平台实现。

### 4.2 CPU_OFF：关闭一个 CPU

```text
Linux CPU hotplug teardown
    -> psci_cpu_off()
    -> SMC: PSCI_CPU_OFF
    -> TF-A PSCI Runtime Service
    -> 平台 pwr_domain_off()
    -> 直接控制电源，或请求 SCP / Power Controller
    -> CPU Power Domain OFF
```

`PSCI_CPU_OFF` 与 `PSCI_CPU_SUSPEND` 不同：

- CPU_OFF：当前 CPU 关闭后不从这条执行流返回；以后可以通过 CPU_ON 重新启动。
- CPU_SUSPEND：进入低功耗状态，满足唤醒条件后恢复执行。

### 4.3 CPU Idle / CPU_SUSPEND：进入低功耗状态

```text
Linux cpuidle governor
    -> cpuidle driver
    -> PSCI CPU_SUSPEND
    -> TF-A PSCI
    -> 平台 pwr_domain_suspend()
    -> 直接控制电源域，或请求 SCP
    -> CPU / Cluster 进入低功耗状态
    -> 中断 / 定时器 / 外部事件唤醒
    -> TF-A resume path
    -> Linux resume
```

常见状态：

- **WFI**：处理器等待中断，不意味着 CPU 电源域一定关闭。
- **Retention**：保留部分上下文或电源状态，以降低功耗并支持较快恢复。
- **CPU Power Down**：关闭 CPU 核的部分或大部分电源。
- **Cluster Power Down**：整个簇进入更深的低功耗状态。
- **System Suspend**：系统级挂起，可能涉及 DRAM 自刷新、互连和更多电源域。

具体状态由平台 PSCI 实现、DTS、cpuidle driver 和硬件能力决定。

### 4.4 System Power：系统级关机、重启和挂起

常见 PSCI 操作包括：

- `PSCI_SYSTEM_OFF`
- `PSCI_SYSTEM_RESET`
- `PSCI_SYSTEM_SUSPEND`（是否支持需核对平台和版本）

TF-A 最终可能直接操作 SoC 系统控制器，也可能通过平台定义的方式请求 SCP 执行系统级状态转换。

## 5. QEMU 与 FVP 对比

| 维度 | QEMU `virt` | Arm FVP |
|---|---|---|
| Linux 启动、TF-A 启动链 | 适合 | 适合 |
| PSCI CPU_ON/OFF | 适合 | 适合 |
| Linux CPU hotplug | 适合 | 适合 |
| cpuidle / suspend | 可做基础验证，深度取决于模型 | 取决于平台模型 |
| 独立 SCP 固件 | 标准 `virt` 通常不提供真实 SCP 模型 | 某些平台支持，需核对具体模型 |
| SCMI / Power Domain | 取决于 QEMU 设备模型和配置；也可使用专门模拟方案 | SGI-575 等平台更适合做 SCP/SCMI 实验 |
| 真实 SoC 电源行为 | 不等价 | 仍是模型行为，不等价于真实芯片 |

建议顺序：

1. 复用现有 QEMU 工程，把 PSCI CPU_ON/OFF 跑通。
2. 使用 SGI-575 FVP + SCP-firmware，研究 SCMI 和 Power Domain。
3. 迁移到 Cortex-A78AE 实际平台，核对 SoC 电源域拓扑、PSCI 实现和 AP-SCP 通信链路。

AEMv8-A Base FVP 适合通用 Arm 架构实验，但不能默认它具有完整 SCP 参考平台。获取 FVP 前应确认模型、配套固件和软件包权限。

## 6. 阶段一：QEMU 中验证 PSCI

你现有的 QEMU AArch64、TF-A、OP-TEE 和 Linux 工程可以继续使用。示例命令（按现有镜像和启动链调整）：

```bash
qemu-system-aarch64 \
    -machine virt,secure=on,virtualization=on \
    -cpu cortex-a72 \
    -smp 4 \
    -m 2G \
    -nographic
```

### 6.1 检查 Linux 是否使用 PSCI

```bash
dmesg | grep -i psci

dtc -I fs -O dts /sys/firmware/devicetree/base > /tmp/running.dts
grep -n -A8 -B2 -i psci /tmp/running.dts
```

常见设备树节点示例：

```dts
psci {
    compatible = "arm,psci-1.0";
    method = "smc";
};
```

实际属性以运行时设备树为准。

### 6.2 检查 CPU 状态并执行 hotplug

```bash
cat /sys/devices/system/cpu/present
cat /sys/devices/system/cpu/online

# 下线 CPU1
echo 0 | sudo tee /sys/devices/system/cpu/cpu1/online

# 再上线 CPU1
echo 1 | sudo tee /sys/devices/system/cpu/cpu1/online
```

CPU0 通常不能通过通用 sysfs hotplug 接口下线。操作前应确认目标 CPU 上没有关键任务，并保留可恢复的控制台访问。

### 6.3 Linux 侧源码

重点目录：

```text
drivers/firmware/psci/
```

检索：

```bash
grep -R -n -E 'psci_cpu_on|psci_cpu_off|CPU_SUSPEND' \
    drivers/firmware/psci arch/arm64
```

重点理解：

- PSCI driver 如何从 DT/ACPI 发现 PSCI。
- Linux 如何封装 PSCI function ID 和参数。
- CPU hotplug 如何进入 PSCI CPU_OFF / CPU_ON。
- cpuidle driver 如何选择 PSCI suspend state。

### 6.4 TF-A 侧源码

PSCI 通用代码通常位于：

```text
services/std_svc/psci/
```

可重点查看（文件布局随版本变化）：

```text
psci_main.c
psci_setup.c
psci_common.c
psci_on.c
psci_off.c
psci_suspend.c
```

检索平台电源回调：

```bash
grep -R -n -E \
'pwr_domain_on|pwr_domain_off|pwr_domain_suspend|pwr_domain_on_finish|pwr_domain_suspend_finish' \
plat services
```

建议在平台回调中增加日志，打印 MPIDR、电源状态、返回值、SCP 请求结果和超时信息。

### 6.5 重要陷阱：确认 PSCI SMC 到底由谁处理

QEMU `virt` 的 PSCI 服务可能由 QEMU/KVM 提供。如果当前启动方式没有执行你编译的 TF-A BL31，修改 TF-A 的 PSCI 代码后可能看不到日志。

先确认：

1. 当前启动链是否加载了你的 TF-A BL31。
2. PSCI SMC 是否真正进入 BL31。
3. PSCI Runtime Service 是由 BL31 处理，还是由 QEMU/KVM 提供。
4. 能否通过 BL31 日志或 GDB 断点确认执行路径。

Linux 打印了 PSCI 信息，并不能单独证明请求进入了你修改的 TF-A 代码。

## 7. 阶段二：QEMU 中观察 cpuidle

### 7.1 查看 cpuidle state

```bash
for d in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
    echo "=== $d ==="
    for f in name desc latency residency usage time; do
        [ -f "$d/$f" ] && printf '%s: ' "$f" && cat "$d/$f"
    done
done
```

查看设备树：

```bash
grep -n -A30 -B5 'cpu-idle-states' /tmp/running.dts
grep -n -A15 -B3 'entry-method' /tmp/running.dts
```

常见属性可能包括：

```dts
entry-method = "psci";
arm,psci-suspend-param = <...>;
```

具体格式应结合当前内核版本和设备树 binding 文档确认。

### 7.2 记录 idle 和调度 trace

```bash
sudo trace-cmd record \
    -e power:cpu_idle \
    -e power:cpu_frequency \
    -e sched:sched_switch \
    -e sched:sched_waking
```

结束采集后：

```bash
sudo trace-cmd report
```

也可以使用 Perfetto 观察调度、唤醒和 CPU idle 轨迹。

**注意：`power:cpu_idle` 反映 Linux 观察到的 idle 状态切换，不能单独证明芯片物理 CPU/Cluster 电源域确实断电。** 需要结合平台电源控制器状态、SCP 日志、硬件计数器或芯片调试接口验证。

## 8. 阶段三：获取并构建 SCP-firmware

官方仓库：

<https://git.gitlab.arm.com/firmware/SCP-firmware.git>

克隆：

```bash
git clone --recurse-submodules \
    https://git.gitlab.arm.com/firmware/SCP-firmware.git \
    source/SCP-firmware

cd source/SCP-firmware
git submodule update --init --recursive
```

常见目录概念（实际随版本变化）：

| 目录 | 主要内容 |
|---|---|
| `framework/` | SCP Framework 基础设施 |
| `module/power_domain/` | Power Domain 模块 |
| `module/system_power/` | 系统级电源管理 |
| `module/clock/` | 时钟管理 |
| `module/performance/` | 性能管理 |
| `module/scmi/` | SCMI 协议服务 |
| `module/transport/` | SCMI 传输层 |
| `product/` | 产品级模块组合和配置 |
| `platform/` | 平台实现 |
| `arch/` | 架构相关代码 |
| `config/` | 构建配置 |

### 8.1 SCP Framework 初始化模型

重点理解这些阶段：

1. Module initialization
2. Element initialization
3. Post-initialization
4. Bind
5. Start

运行阶段通常由模块事件、消息、通知或中断驱动。建议沿 SCMI 请求进入模块的路径，追踪到 Power Domain 的状态转换。

### 8.2 SGI-575 构建示例

某些版本可使用类似命令：

```bash
make -f Makefile.cmake \
    PRODUCT=neoverse-rd/sgi575 \
    MODE=debug
```

这是示例命令。实际 product 名称、构建系统和参数必须以当前 checkout 的 README、构建文档和产品目录为准。

### 8.3 SCP 启动顺序并非固定

常见模式：

- SCP Boot ROM 启动 SCP，再加载 SCP runtime firmware；SCP 初始化 SCMI 后，AP 才继续启动或请求电源服务。
- AP 侧 TF-A BL2 加载 SCP runtime firmware。
- 不同平台可能采用不同启动顺序和固件交付方式。

因此不能把某个平台的启动顺序当成通用规律。应查看目标平台启动文档、TF-A platform code 和 FVP 配置。

## 9. 阶段四：跟踪 Linux SCMI 到 SCP Power Domain

Linux SCMI 源码目录：

```text
drivers/firmware/arm_scmi/
```

重点关注（文件布局可能随内核版本变化）：

```text
driver.c
common.h
protocol.c
power.c
clock.c
perf.c
```

典型路径：

```text
Linux client / genpd / cpufreq
    -> SCMI core
    -> SCMI Power Protocol
    -> SCMI Transport
    -> Mailbox / Shared Memory / MHU
    -> SCP SCMI service
    -> SCP Power Domain module
    -> SoC Power Controller
```

### 9.1 建议跟踪的字段

在 Linux 和 SCP 两端尽量记录：

- SCMI Protocol ID
- Message ID
- Power Domain ID
- requested_state
- response status
- transport channel / token
- 请求发送和响应时间
- Power Domain 当前状态
- 硬件操作结果或超时状态

Power Domain 状态转换可能是异步的。要区分请求受理、状态转换进行中和最终状态，不能假设请求发出后硬件立即达到目标状态。

### 9.2 Linux 配置检查

按平台实际 transport 选择配置，不需要全部启用：

```text
CONFIG_ARM_PSCI_FW
CONFIG_ARM_SCMI_PROTOCOL
CONFIG_ARM_SCMI_TRANSPORT_MAILBOX
CONFIG_ARM_SCMI_TRANSPORT_SMC
CONFIG_CPU_IDLE
CONFIG_CPU_FREQ
CONFIG_FUNCTION_TRACER
CONFIG_FUNCTION_GRAPH_TRACER
CONFIG_DYNAMIC_DEBUG
```

Mailbox 和 SMC transport 应根据设备树、平台设计和固件接口选择。

### 9.3 SCP 端调试

具体方式取决于平台和构建配置，常见手段包括：

- FVP UART / 串口日志。
- SCP-firmware debug 日志。
- SCP CLI（若平台产品配置启用）。
- 在 SCMI service、transport 和 Power Domain 模块中增加日志。
- 对比 AP 请求时间、SCP 收到请求时间和硬件状态变化时间。

先验证最短链路：Linux 发出 SCMI Power Domain 请求，SCP 收到对应 message，模块执行状态转换，并将响应返回 Linux。

## 10. 推荐实验清单

| 实验 | 环境 | 目标 | 验收标准 |
|---|---|---|---|
| Lab 0：确认启动链 | QEMU | 确认 TF-A BL31、Linux、PSCI 关系 | 能解释 PSCI SMC 由谁处理 |
| Lab 1：PSCI CPU_ON | QEMU | 启动离线 CPU | 对应 Linux、SMC、TF-A 和 secondary CPU 日志 |
| Lab 2：PSCI CPU_OFF | QEMU | CPU hotplug 下线 | 确认 CPU_OFF 路径和状态变化 |
| Lab 3：CPU Idle | QEMU | 理解 cpuidle 与 PSCI suspend | 解释 idle state、trace 和 resume |
| Lab 4：SCP 启动 | SGI-575 FVP | 构建并启动 SCP-firmware | 获得 SCP 启动和初始化日志 |
| Lab 5：SCMI 通信 | SGI-575 FVP | 跟踪 SCMI transport | 匹配 Linux 请求与 SCP 响应 |
| Lab 6：Power Domain | SGI-575 FVP | 跟踪状态转换 | 对应 Domain ID、请求状态和最终状态 |
| Lab 7：Suspend/Resume | SGI-575 FVP | 分析深度低功耗和唤醒 | 串起 Linux、TF-A、SCP 和恢复路径 |
| Lab 8：目标平台迁移 | 实际 A78AE SoC | 对比目标平台实现 | 找到电源域拓扑、回调和通信链路 |

## 11. 4～6 周学习计划

### 第 1 周：QEMU + PSCI

- 阅读 Linux PSCI driver。
- 阅读 TF-A PSCI Runtime Service。
- 确认 QEMU 启动链中 PSCI 的实际实现者。
- 执行 CPU1 offline/online。
- 在 Linux 和 TF-A 两侧增加日志。
- 使用 trace-cmd 或 Perfetto 观察 CPU hotplug 和调度。

**阶段产出：** CPU_ON / CPU_OFF 调用链图，以及一份日志和 trace 分析记录。

### 第 2 周：cpuidle + CPU_SUSPEND

- 阅读 Linux cpuidle core 和 PSCI cpuidle driver。
- 阅读设备树 idle-state binding。
- 区分 WFI、retention、CPU power down、cluster power down。
- 分析 CPU_SUSPEND 和唤醒恢复路径。
- 记录 idle trace，明确软件状态与物理电源状态的差别。

**阶段产出：** CPU idle state 与 PSCI suspend state 对照表。

### 第 3 周：FVP + SCP-firmware

- 获取可用的 SGI-575 FVP 和配套软件。
- 构建 SCP-firmware debug 版本。
- 了解 SCP Framework 初始化阶段。
- 追踪 SCMI transport 和 Power Domain 模块。
- 获取 AP 与 SCP 的启动日志。

**阶段产出：** SCP 启动流程图和模块依赖图。

### 第 4 周：SCMI + Power Domain

- 从 Linux SCMI Power driver 开始跟踪。
- 对照 SCMI message、Domain ID 和 SCP 日志。
- 分析 Power Domain 请求、执行和响应。
- 研究 Clock、Reset、Performance 等 SCMI protocol。
- 分析 CPU / Cluster / System 电源状态的协同关系。

**阶段产出：** Linux → SCMI → SCP → Power Controller 端到端调用链。

### 第 5～6 周：迁移到 Cortex-A78AE 实际平台

- 获取目标 SoC 电源域框图和电源管理文档。
- 确认 CPU、Cluster、DSU、GIC、DRAM、系统互连等电源域关系。
- 找到目标平台 TF-A 的 `pwr_domain_*` 回调。
- 确认是否有 SCP，以及 AP 与 SCP 使用的通信机制。
- 对照 FVP 和真实平台差异。
- 在真实板上验证 CPU hotplug、cpuidle、suspend/resume。

**阶段产出：** 目标 SoC 电源管理架构图，以及 CPU_ON、CPU_OFF、CPU_SUSPEND、System Suspend 的实际调用链。

## 12. 调试观测点

| 层次 | 观测内容 | 推荐手段 |
|---|---|---|
| Linux policy | hotplug、cpuidle governor、suspend 请求 | dmesg、trace-cmd、Perfetto |
| Linux PSCI | Function ID、参数、返回值 | 内核日志、源码跟踪、ftrace |
| SMC / EL3 | SMC 入口、PSCI handler | TF-A 日志、GDB、JTAG |
| TF-A platform PM | `pwr_domain_on/off/suspend` 等回调 | `INFO()` 日志、断点 |
| SCMI transport | Protocol ID、Message ID、token、状态 | Linux dynamic debug、SCP 日志 |
| SCP service | SCMI 收包和响应 | SCP debug log、CLI、断点 |
| Power Domain | Domain ID、目标状态、状态转换 | SCP 模块日志、平台状态寄存器 |
| Hardware | 电源、时钟、复位状态 | SoC 寄存器、功耗测量、硬件调试工具 |

建议统一日志格式，包含时间戳、CPU/MPIDR、请求类型、Domain ID、目标状态和结果。通过时间戳和请求参数对齐 Linux、TF-A、SCP 三侧日志。

## 13. 四条核心调用链速查

### CPU_ON

```text
Linux CPU hotplug
 -> psci_cpu_on()
 -> SMC
 -> TF-A PSCI
 -> platform pwr_domain_on()
 -> SCP / Power Controller（若平台采用）
 -> CPU release from reset
 -> TF-A warm entry
 -> Linux secondary CPU startup
```

### CPU_OFF

```text
Linux CPU hotplug teardown
 -> psci_cpu_off()
 -> SMC
 -> TF-A PSCI
 -> platform pwr_domain_off()
 -> SCP / Power Controller（若平台采用）
 -> CPU Power Domain OFF
```

### CPU Idle / CPU_SUSPEND

```text
Linux cpuidle
 -> PSCI CPU_SUSPEND
 -> TF-A PSCI
 -> platform pwr_domain_suspend()
 -> SCP / Power Controller（若平台采用）
 -> CPU / Cluster low-power state
 -> Wakeup event
 -> TF-A resume path
 -> Linux resume
```

### System Power

```text
Linux system suspend / shutdown / reboot
 -> PSCI SYSTEM_SUSPEND / SYSTEM_OFF / SYSTEM_RESET
 -> TF-A
 -> Platform PM
 -> SCP / System Power Controller（若平台采用）
 -> System state transition
```

## 14. 官方资料与源码入口

建议优先阅读官方文档和与你使用版本对应的源码：

1. **TF-A Porting Guide**：PSCI power domain topology、平台电源回调和移植要求。
2. **TF-A 源码**：`services/std_svc/psci/` 和具体平台的 `plat/` 目录。
3. **SCP-firmware 官方仓库与 User Guide**：Framework、模块、产品配置、构建和调试。
4. **SCP Framework Guide**：模块初始化、元素绑定、事件和运行模型。
5. **Linux PSCI driver**：`drivers/firmware/psci/`。
6. **Linux SCMI driver**：`drivers/firmware/arm_scmi/`。
7. **Linux cpuidle**：`drivers/cpuidle/` 及 ARM64 PSCI idle driver。
8. **Arm FVP 文档**：确认所下载 FVP 的平台能力、启动参数和 SCP 支持情况。

官方入口：

- TF-A：<https://trustedfirmware-a.readthedocs.io/>
- SCP-firmware：<https://git.gitlab.arm.com/firmware/SCP-firmware>
- Arm FVP：<https://developer.arm.com/Tools%20and%20Software/Fixed%20Virtual%20Platforms>
- Linux Kernel 文档：<https://docs.kernel.org/>

## 15. 最终建议

不要一开始就把所有精力放在 SCP 上。先在 QEMU 中确认 Linux PSCI、TF-A PSCI handler 和 CPU_ON/OFF 的关系，尤其要弄清当前 QEMU 启动链究竟由谁处理 PSCI SMC。

之后转向 SGI-575 FVP，重点研究 SCMI transport、SCP Framework 和 Power Domain 模块。最后将这套分析方法迁移到 Cortex-A78AE 目标 SoC，结合真实平台的电源域拓扑和硬件控制方式完成验证。

**最关键的分析原则：把 Linux 策略请求、PSCI/SCMI 软件接口、TF-A/SCP 固件执行、硬件电源状态这四层分开观测，再通过时间戳和请求参数把它们关联起来。**

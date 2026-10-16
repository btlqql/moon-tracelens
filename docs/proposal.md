# Moon TraceLens——离线日志归一化、关联分析与基线差异比较组件

项目账号：btlqql  
主要语言：MoonBit；开源许可：Apache-2.0  
仓库：[https://github.com/btlqql/moon-tracelens](https://github.com/btlqql/moon-tracelens)  
修订版本：0.2.0；日期：2026-10-16  
公开包：[moon_tracelens@0.2.0](https://mooncakes.io/docs/btlqql/moon_tracelens@0.2.0)

> 本稿供个人参考。正文按本次实际实现说明功能和边界；公开提交、CI 及包发布状态另附核对记录。修改材料不代表主办方已重新审核通过。

## 一、项目简介

TraceLens 使用 MoonBit 对离线日志归一化、排序、筛选和分组，输出事件时间线、错误计数、错误比例及延迟 p95。当前修订补充 baseline 与 current 两批日志的指标比较，并按同一分组维度对齐新增、移除和持续存在的服务或请求组，保留两侧解析诊断。

## 二、使用问题与组件职责

排查服务变更时，两份日志的数量、错误比例与延迟可能同时变化，仅逐条查看日志难以定位差异所在。TraceLens 提供可重复的批次比较，适合发布前后检查、离线故障复盘及多来源请求串联。输入数据和观察窗口由调用方选定，报告不据此自动推断变更的因果关系。

## 三、核心机制与实现

### 日志归一化与坏行处理

输入支持事件数组、JSONL 和五列 pipe 文本。时间可使用有限 epoch 秒或受支持的 RFC3339 表示，级别归一化后按时间排序。pipe 的缩进后续行可附加为堆栈内容。原始来源和行号进入报告，便于定位。

本次修复后续行归属：坏记录会中断当前堆栈归属，孤立缩进行进入诊断，而不会拼到更早的正常事件；独立提供的两个来源即使名字相同，也不会共享堆栈上下文。反向时间窗口被拒绝，正常筛选采用 since 包含、until 不包含的区间。

### 时间线与指标

分析支持字段相等、文本包含与时间窗口筛选，按 request_id 或调用方指定字段分组。每组报告时间线及 elapsed_seconds，指标包括 count、errors、error_fraction、duration_p95_ms 和级别分布。p95 使用排序后的最近秩方法。错误级别为 error 和 fatal；错误比例分母为实际参与分析的有效事件数。

### 基线比较

新增 operation=compare，before 和 after 分别为分析请求，并要求相同 group_by。先独立归一化与筛选，再以分组键的稳定表示对齐组，返回 added、removed、retained。全局和各组均提供 before、after、delta；新增或移除组的计数侧补零，空侧错误比例和无样本的延迟保持 null，不能当成 0% 或零延迟。

before_diagnostics 与 after_diagnostics 分别保留坏行。complete 仅表示两侧没有摄入诊断，不表示输入覆盖全部真实日志，也不表示存在统计显著性。指标差值是 after 减 before，没有按观察时长归一为吞吐率。

## 四、完整案例

### 案例一：请求故障复盘

读取真实的本地合成 pipe 和 JSONL 文件，归一化三个事件、识别一条错误事件，将合法堆栈续行附到对应消息。坏 JSONL 行进入诊断，同一请求时间线显示起止相差一秒。修订回归用例另验证坏行后的缩进内容不能附到上一条正常消息。

### 案例二：服务基线对齐

基线含服务 a 的正常事件和服务 b 的错误事件，当前批次含 a 的错误事件和 c 的正常事件。报告把 a 标为 retained、b 标为 removed、c 标为 added。两侧总体均有两条事件和一条错误，但 a 的错误数增加一条，说明仅看总体计数会遗漏服务间变化。基线延迟 p95 为 20ms、当前为 30ms，差值为 10ms。

### 案例三：空基线与不完整摄入

没有基线事件时，基线比例及比例差值保持 null。当前侧存在坏 JSONL 时，报告保留其物理行号并标记 complete=false，而不以“有效事件为零”宣称当前侧没有错误。比较不同 group_by 的请求直接拒绝。

## 五、工程结构与可复核验证

领域计算位于 MoonBit 核心，标准 JSON 通过 execute 转换为语义值并调用 run。cmd/main 提供 JS CLI；核心可面向 JS、wasm、wasm-gc、native 测试，宿主脚本单独承担文件读取与参考核对。数据来自合成固定样本和确定性随机数据，没有声明真实生产用户或商业部署。

当前包含 14 项 MoonBit 测试，以及通过真实 Node CLI 执行的 12 组 JSON 夹具。独立 Python datetime 检查覆盖 50 组日历、时区与小数秒；新增 20 对随机日志窗口，以独立计数、错误比例和最近秩 p95 验证总体及服务分组结果。 新案例输入见 examples/scenario-4.json；完整断言位于 tests/cases.json 和新增回归测试文件。

复核命令：

```sh
moon update
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon test --target native
moon build --target js
node scripts/check.mjs
python -B scripts/reference.py
moon run cmd/main --target js -- examples/scenario-4.json
```

native 需要 C 编译器；实际执行后端、结果及对应版本以交付核对记录和公开 CI 为准，不能将“提供测试命令”当成“测试已经通过”。

## 六、针对初审反馈的工程修订

所提供通知指出：GitHub 仓库自 2026 年 9 月 1 日后的提交不足 10 次。修订前公开 main 分支核查为 5 次。本次围绕输入或状态错误修复、回归测试、新增领域能力、独立对照用例和版本文档逐步提交，使用真实当日时间，保留原有历史。

开发记录可在 [公开 main 历史](https://github.com/btlqql/moon-tracelens/commits/main/) 核对；最终提交数量、日期及哈希见配套提交核对表。本次没有创建空提交、倒填日期或将既有成果重写成虚假历史。提交数达到通知所述数量只解决该项可核对条件，不等同于项目规模、独立价值或最终验收已经获认可。

## 七、来源、复用与当前边界

领域实现和本次新增机制随仓库开源。MoonBit 标准库、Node 内置模块及 Python 标准库分别用于运行、宿主操作或独立核对；来源说明见 THIRD_PARTY.md。共享 JSON/CLI 脚手架按基础设施说明，不将其当成不同项目各自独有的领域创新。

本项目是离线批次分析工具，没有实时 tail、轮转断点恢复、分布式采集器或完整 OpenTelemetry 导出。RFC3339 采用大写 T/Z，不接受闰秒。比较不提供因果推断、统计显著性和自动发布结论；指标均由有效且经过筛选的事件计算，须结合诊断阅读。

本稿撤去旧参考方案中尚未完成的高级能力、生产规模和性能目标。当前功能、测试与开发记录可以实际复核；项目仍是持续完善的组件，不能把原先 4,000–8,000 行内部目标写成已经交付的代码量。

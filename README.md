# 工业设计三联海报自动编排器

本系统将工作拆成两部分：

- **AI 图像层**：只生成产品母版、场景、结构细节、应用场景等无文字图像资产。
- **模板信息层**：脚本原生绘制标题、中英文说明、分析卡、流程图、CMF 色板、数据图和页脚，然后导出三张海报。

这样避免把中文、图表、尺寸或产品事实交给图像模型生成。

## 输入

每个项目一个 JSON 文件：

`projects/<project-id>/project.json`

其中包含项目名称、产品事实、文案、流程、模块、数据和资产路径。可从：

`projects/nebula-orbit-x/project.json`

复制开始新项目。

## 执行

在 `D:\桌面\工业设计` 下运行：

```powershell
.\poster-automation\scripts\run-project.ps1 `
  -ProjectFile .\poster-automation\projects\nebula-orbit-x\project.json `
  -OutputDir .\Outputs\08_Exports\nebula-orbit-x `
  -Preset preview
```

该单一命令依次执行资料校验、三张海报编排及导出 QA，并在输出目录写入 `QA-REPORT.json`。`preview` 为 1754 × 2483 px，便于快速检查。

```powershell
.\poster-automation\scripts\run-project.ps1 `
  -ProjectFile .\poster-automation\projects\nebula-orbit-x\project.json `
  -OutputDir .\Outputs\08_Exports\nebula-orbit-x `
  -Preset a1-150ppi
```

`a1-150ppi` 为 3508 × 4967 px；`a1-300ppi` 为 7016 × 9933 px。最终印刷前仍须根据印厂 ICC、出血和 PDF 规范另行输出；当前脚本默认导出 RGB PNG。

## 目录约定

```text
poster-automation/
  projects/<project-id>/project.json  # 可机器读取的资料包
  schemas/project-brief.schema.json   # 字段契约
  scripts/validate-project.ps1        # 资料、路径与内容校验
  scripts/build-posters.ps1           # 三张海报编排与导出
  scripts/qa-exports.ps1              # PNG 存在性、尺寸与 PPI 检查
  scripts/run-project.ps1             # 校验 → 编排 → QA 的单一入口
```

## 约束

- 所有可读文字、图标、图表、连线和色板由脚本绘制。
- 图片资产应使用已批准的产品/场景图；脚本不改写产品结构。
- `sourceImages` 不足分辨率时，校验器会报告警告；不能靠改 PPI 元数据解决。
- 未填的指标应使用概念性描述或留空，不能虚构医疗认证、临床结果或工程性能。

# 缺陷跟踪库（bugtrace）

> 本目录维护 HodoopForge / EduLake 平台所有已发现缺陷的**全生命周期跟踪**。
> 主表：`BUG_REGISTRY.md`；单条复杂缺陷可另建 `bugs/BUG-xxx-*.md` 详述。

## 状态流转

```
NEW → TRIAGED → IN_PROGRESS → FIXED → VERIFIED → CLOSED
                          ↘ WONTFIX / DUPLICATE / CANNOT_REPRO
```

## 字段说明

| 字段 | 含义 |
|---|---|
| ID | `BUG-<三位序号>` |
| 标题 | 简明描述 |
| 严重级别 | `S0 致命` / `S1 严重` / `S2 一般` / `S3 轻微` |
| 优先级 | `P0` / `P1` / `P2` |
| 状态 | 见流转图 |
| 首次发现 | 日期 |
| 影响范围 | 服务/组件/节点 |
| 根因 | 一句话根因 |
| 修复方案 | 关键动作 |
| 关联 | commit / 文档 / 告警名 |

## 维护约定

1. 新缺陷先登记 `BUG_REGISTRY.md`，再按需建详情文件。
2. 修复后在 `func/CHANGELOG.md` 同步登记。
3. 每个阶段总结（`func/sessions/`）应引用相关 BUG ID。
4. 定期（每迭代）复核 `VERIFIED` 项并关闭。

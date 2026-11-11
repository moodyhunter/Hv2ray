# 备份还原（core/backup）

这里放 Hv2ray 全部备份/还原的格式定义与逻辑。两条入口共用同一套规则：

| 入口 | 触发方式 | 落点 |
| --- | --- | --- |
| 应用内导出/导入 | Settings 页「备份与还原」，文件选择器选一个 `.json` | 用户选的备份文件 |
| 系统级备份还原 | 换机克隆、云备份、应用迁移时由系统调用 `EntryBackupAbility` | 配置目录内的 `backup.json` |

## 1. 分层

| 文件 | 职责 |
| --- | --- |
| `BackupModel.ets` | 格式定义、解析、校验、数据修复、快照 ↔ 配置文件的互相转换、还原决策。**纯逻辑**。 |
| `BackupStore.ets` | 唯一读写文件系统的地方：列目录、读文本、写文本、调用 `ConfigManager`。 |
| `../../entrybackupability/EntryBackupAbility.ets` | 系统备份还原的生命周期钩子，只做日志和调用上面两个文件。 |

`BackupModel.ets` 刻意不 import 任何系统 API（`fs` / `hilog` / `application` / `BuildProfile`）。原因有两个：

- Local Test（`entry/src/test/`）不支持系统 API，纯逻辑才能在 PC 上跑用例；
- 应用内导出导入和系统级备份必须走同一份格式与决策，不能有第二套实现。

`BuildProfile` 的 `VERSION_CODE` / `VERSION_NAME` 只在 `BackupStore.currentAppVersion()` 一处读取。

## 2. 运行期数据

配置目录来自 `ConfigManager.configDirPath`：

```
<filesDir>/config/            # debug 构建下这个目录名是 config-debug/
├── groups.json               # 分组 + 连接索引（id、name、metadata）
├── settings.json             # WireGuard 设置
├── connections/<connId>.json # 每个连接一份完整 v2ray 配置
└── backup.json               # 本模块写的合并快照（见第 4.2 节）
```

`backup.json` 不参与收集：`listConfigFiles()` 只取 `groups.json`、`settings.json` 和 `connections/*.json`，否则快照会被当成一份配置反复套娃。

## 3. 物理格式

### 3.1 备份文件（信封 envelope）

一个 UTF-8、两空格缩进的 JSON 文档。以下示例由实际代码（`createBackupEnvelope` + `encodeBackupEnvelope`）生成：

```json
{
  "format": "hv2ray-backup",
  "version": 1,
  "createdAt": 1749892323000,
  "appVersion": {
    "code": 1000000,
    "name": "1.0.0"
  },
  "snapshot": {
    "groups": [
      {
        "id": "default",
        "name": "Default",
        "connections": [
          "aB3xK9qL"
        ]
      },
      {
        "id": "subscription",
        "name": "Subscription",
        "connections": []
      }
    ],
    "connections": [
      {
        "id": "aB3xK9qL",
        "name": "HK-01",
        "metadata": {
          "generated": false
        },
        "config": {
          "remarks": "HK-01",
          "server": "203.0.113.9",
          "port": 443
        }
      }
    ],
    "settings": {
      "privateKey": "kW8...",
      "peerPublicKey": "cJ9...",
      "peerEndpoint": "198.51.100.7:51820",
      "localIp": "100.64.0.2/32",
      "mtu": 1420,
      "keepaliveInterval": 25,
      "routes": [
        "100.64.0.0/10"
      ]
    }
  }
}
```

字段含义：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `format` | string | 固定 `hv2ray-backup`（`BACKUP_FORMAT`）。不是这个值的 JSON 直接判为 `not_backup`，不会去猜它的内容。 |
| `version` | number | 格式版本，写出的是 `BACKUP_FORMAT_VERSION`；读取接受 `[BACKUP_MIN_SUPPORTED_VERSION, BACKUP_FORMAT_VERSION]`。 |
| `createdAt` | number | 生成时刻，epoch 毫秒。只用于展示与排查，不参与任何判断。 |
| `appVersion` | object | 生成这份备份的应用版本（`code` = versionCode，`name` = versionName）。用于还原决策，见第 5 节。 |
| `snapshot.groups[]` | array | `{ id, name, connections: string[] }`，与运行期 `IGroup` 同构。 |
| `snapshot.connections[]` | array | `{ id, name, metadata, config? }`。`metadata` 是 `groups.json` 里那份连接元数据原样搬运；`config` 是 `connections/<id>.json` 的内容，缺文件时该字段缺失（而不是写空对象）。 |
| `snapshot.settings` | object | `settings.json` 原样搬运。 |

**没有 schema 迁移层，因为不做有损反序列化**：`metadata` / `config` / `settings` 都按 `object` 搬运，Hv2ray 不认识的字段也照样带回来。所以新增字段不需要升版本；只有**结构本身**变了才需要升 `version` 并在这里加读取分支。

`decodeBackupEnvelope()` 的判定顺序（任一不通过就返回 fatal issue，不给半成品）：

1. 空串 / `null` / 不是合法 JSON → `not_json`
2. `format` 不匹配 → `not_backup`
3. `version` 不是数字 → `not_backup`；大于当前 → `format_too_new`；小于下限 → `format_too_old`
4. `snapshot` 不是对象 → `no_groups_file`；内部读不动 → `not_backup`

### 3.2 快照 ↔ 配置目录

`renderBackupConfigFiles(snapshot)` 摊平成一组相对路径 + 文本；`collectBackupSnapshot(files)` 是反向。两者共用同一份 `snapshot` 形状：`groups.json` 的顶层就是 `{ groups, connections }` 这一层，信封里的 `snapshot` 也是这一层加 `settings`，所以解析函数只有一个（`parseSnapshotParts`）。

上面那份快照渲染出的文件：

```
groups.json
settings.json
connections/aB3xK9qL.json
```

`groups.json` 的内容：

```json
{
  "groups": [
    {
      "id": "default",
      "name": "Default",
      "connections": [
        "aB3xK9qL"
      ]
    },
    {
      "id": "subscription",
      "name": "Subscription",
      "connections": []
    }
  ],
  "connections": [
    {
      "id": "aB3xK9qL",
      "name": "HK-01",
      "metadata": {
        "generated": false
      },
      "config": {
        "remarks": "HK-01",
        "server": "203.0.113.9",
        "port": 443
      }
    }
  ]
}
```

两点需要知道：

- 写回的 `groups.json` 里每个连接会**多带一份 `config`**（`IBackupConnection` 的完整形状）。这不影响正确性：`Connection.Fill()` 只读 `id` / `name` / `metadata`，真正的配置仍从 `connections/<id>.json` 读；下一次 `saveConfigurations()` 会把它去掉。反过来 `collectBackupSnapshot()` 不读 `groups.json` 里的 `config`，只按 id 去挂对应的独立文件，所以两个方向都稳定。
- `config` 缺失的连接不会生成 `connections/*.json`，只留一条 `missing_connection_config` 提醒。

### 3.3 备份文件名

`hv2ray-backup-YYYYMMDD-HHMM.json`（`suggestBackupFileName`），在文件管理器里按时间自然排序。后缀由 `BACKUP_FILE_SUFFIX` 定义，Settings 页的选择器过滤项也用它，不会写两份。

## 4. 两条入口的时序

### 4.1 应用内导出

`exportBackupToUri(uri)`：读配置目录 → `collectBackupSnapshot` → 有 fatal 就拒绝导出（不写半个文件出来）→ 否则用当前版本和时间戳包成信封写入目标文件（picker 授权后的 URI 直接走 `fs.open`）。

### 4.2 应用内导入

`importBackupFromUri(uri)`：读文件 → `decodeBackupEnvelope`（不可用直接失败，本机数据不动）→ `renderBackupConfigFiles` 写回配置目录（写失败即中止，已写出的文件不回滚）→ 刷新 `backup.json` → `ConfigManager.reloadConfigurations()` 把新数据推进内存并通知界面重建。

导入是**覆盖**语义，不是合并：备份里没有的分组和连接会从 `groups.json` 中消失。磁盘上遗留的 `connections/*.json` 不会被删除，但它们不再被引用，因此不可见。正在运行的内核不会自动重启，新配置在下次启动 VPN 时生效。

### 4.3 系统级

- `onBackup()`：`writeConsolidatedBackup(configDir)` 在配置目录里写一份 `backup.json`。备份框架搬运的是整个目录（`backup_config.json` 未配 `includes` 时，框架默认已覆盖 `data/storage/el2/base/files/`），这份自描述快照的作用是：让还原端能判断数据来自哪个版本，并在文件被部分搬运/损坏时提供一份可重建的依据。读不出可用数据时会**删掉**旧的 `backup.json`，避免用坏快照去盖掉还好的数据。
- `onRestore(bundleVersion)`：`restoreSystemBackup(configDir, sourceVersion)` 按第 5 节的决策处理，然后把结论写日志（`repair` / `keep` / `reset` + reason）。

这里不重写业务数据的搬运：`backup_config.json` 里未配置 `fullBackupOnly`（默认 false），框架仍以 `/` 为根把文件解压回原路径。

## 5. 还原决策

`planBackupRestore(input)` 只看三件事：数据来自哪个版本、快照能不能用、`groups.json` 能不能用。原则是**能修就修，拿不准就不动用户的数据，只有确实不可用才推倒重来**。

| 条件 | 结果 |
| --- | --- |
| `sourceVersion.code > 当前 versionCode` | `keep` —— 数据来自更新的版本，不能用旧版本的序列化器去重写它 |
| 快照不可用（缺 `backup.json` 或其中有 fatal），但 `groups.json` 可用 | `keep` —— 保留框架已经恢复好的文件 |
| 快照不可用，且 `groups.json` 也不可用 | `reset` —— 删掉 `groups.json` 和 `backup.json`，应用下次启动时按默认分组重建 |
| 快照可用且无 fatal | `repair` —— 用快照重写 `groups.json` / `settings.json` / `connections/*.json` |

判定 `groups.json` 是否「可用」= 能解析出至少一个分组（`isGroupsFileUsable`）。

## 6. 问题码

所有检查返回 `IBackupIssue { code, detail, fatal }`，不抛异常、不静默丢数据。UI 按 `code` 取本地文案（`Settings.backupFailureText`），`detail` 只进日志。

| code | fatal | 含义与处理 |
| --- | --- | --- |
| `not_json` | 读备份文件时是；配置目录里 `settings.json` 坏掉时否 | 空文件或不是合法 JSON |
| `not_backup` | 是 | 不是 Hv2ray 的备份：`format` 不对、没有 `version`、或 payload 读不动 |
| `format_too_new` | 是 | 备份格式比当前构建新 |
| `format_too_old` | 是 | 低于 `BACKUP_MIN_SUPPORTED_VERSION` |
| `no_groups_file` | 是 | 没有 `groups.json`，或信封里没有 `snapshot` |
| `invalid_group` | 否 | 条目没有 `id`，跳过该条目 |
| `duplicated_group` / `duplicated_connection` | 否 | 同一个 id 出现多次，只保留第一个 |
| `unknown_connection` | 否 | 分组引用了不存在的连接，去掉这个引用，其余数据保留 |
| `missing_connection_config` | 否 | 连接没有配置文件，或该文件不是合法 JSON |
| `orphan_connection_config` | 否 | `connections/` 下有文件不被 `groups.json` 引用，不纳入备份 |

## 7. 用例位置

| 位置 | 覆盖 | 怎么跑 |
| --- | --- | --- |
| `../../../../test/BackupModel.test.ets` | 格式、修复、映射、还原决策等纯逻辑（不需要设备） | `hvigorw test -p module=entry`（需要完整 SDK，CLT 里缺本地测试运行时则只能编译） |
| `../../../../ohosTest/ets/test/BackupStore.test.ets` | 真实沙箱文件的收集、快照写入、修复/保留/重置、以及经过 `ConfigManager` 的端到端导出导入 | 连上设备后 `hdc shell aa test -b me.moody.hv2ray -m entry_test -s unittest OpenHarmonyTestRunner` |

改格式时两边都要过：新增 `version` 分支就补一条「过新/过旧」的用例，改修复规则就补对应的 `planBackupRestore` 用例。

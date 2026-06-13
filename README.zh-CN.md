# SQLink / MySQL Client Mobile

[English](README.md)

SQLink 是一款面向 iPhone 和 iPad 的 SwiftUI MySQL 客户端。Xcode 产品名为
`MySQLClientMobile`，应用显示名为 `SQLink`。

项目同时包含基于 `mysql-nio` 的真实 MySQL 连接层，以及用于 UI 开发和兜底的
Mock 服务。当前能力覆盖连接管理、数据库浏览、表数据编辑、SQL 工作台、查询历史、
收藏 SQL，以及适合移动端使用的 CSV/JSON 导入导出流程。

## 功能特性

- 连接配置：host、port、username、默认数据库、TLS 开关、只读模式、连接测试，以及
  基于 Keychain 的密码保存。
- 自适应 SwiftUI 导航：iPhone 使用 TabView，iPad 使用 `NavigationSplitView`。
- 数据库浏览：schema、表、视图、存储过程、函数、触发器、字段、索引和
  `SHOW CREATE` DDL。
- 表数据浏览：分页、表格/卡片视图、筛选、排序、行详情、新增、编辑和删除。
- SQL 编辑器：执行、格式化、`EXPLAIN`、查询历史、收藏、结果导出，以及高风险 SQL
  二次确认。
- 表数据结果和 SQL 查询结果支持 CSV/JSON 导出。
- CSV 导入：文件选择、预览、字段映射、空字符串按 NULL 导入、逐行插入、进度和
  成功/失败统计。
- 使用 SwiftData 本地保存连接元数据、查询历史和收藏 SQL。
- 可选应用锁：通过 LocalAuthentication 使用 Face ID、Touch ID 或设备密码解锁。
- SQL 安全检查：只读连接、`DROP`、`TRUNCATE`、无 `WHERE` 的 `UPDATE`/`DELETE`
  等风险提示和阻断。

## 项目信息

| 项目 | 值 |
| --- | --- |
| 应用显示名 | `SQLink` |
| Xcode 产品名 | `MySQLClientMobile` |
| Bundle ID | `com.devonchan.MySQLClientMobile.dev` |
| 版本 | `1.0.0` |
| iOS Deployment Target | `17.0` |
| Swift 版本 | `5.9` |
| 推荐 Xcode | `16+` |
| 主要 MySQL 依赖 | `mysql-nio` `1.9.1` |

## 快速开始

1. 使用 Xcode 打开 `MySQLClientMobile.xcodeproj`。
2. 等待 Xcode 解析 Swift Package 依赖。必要时执行
   `File > Packages > Resolve Package Versions`。
3. 选择 iPhone 或 iPad 模拟器，也可以选择真机。
4. 构建并运行 `MySQLClientMobile` target。
5. 新建 MySQL 连接配置，填写 host、port、username 和 password，先测试连接，再正式连接。

如果连接局域网内的 MySQL 服务器，iOS 可能会弹出本地网络权限提示。项目已经在
`Info.plist` 中配置了 `NSLocalNetworkUsageDescription`。

## 依赖

Xcode 工程通过
`MySQLClientMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
解析 Swift Package。主要直接依赖包括：

- `https://github.com/vapor/mysql-nio.git`，固定版本 `1.9.1`
- `https://github.com/apple/swift-nio.git`
- `https://github.com/apple/swift-nio-ssl.git`
- `https://github.com/apple/swift-log.git`

当可以导入 `MySQLNIO` 时，应用默认使用真实 MySQL 服务：

```swift
#if canImport(MySQLNIO)
@StateObject private var session = MySQLSessionStore(client: MySQLNIOClientService())
#else
@StateObject private var session = MySQLSessionStore(client: MockMySQLClientService())
#endif
```

## 架构

- `MySQLClientMobile/App`：应用入口、自适应根导航、外观选择、SwiftData 模型容器和
  LocalAuthentication 应用锁。
- `MySQLClientMobile/Core`：领域模型、SwiftData 存储模型、Keychain 服务、MySQL 服务协议、
  真实 `MySQLNIOClientService`、Mock 服务、SQL 格式化/导入/导出工具和 SQL 安全检查。
- `MySQLClientMobile/Features`：连接管理、数据库浏览、SQL 编辑器、表数据 UI、表结构设计器、
  导入导出、历史记录、收藏和设置。
- `MySQLClientMobile/DesignSystem`：共享 SwiftUI 组件，包括玻璃卡片、徽标、顶部提示、
  错误提示、空状态和数据表格。

## MySQL 能力

真实的 `MySQLNIOClientService` 当前支持：

- 连接、断开连接，以及通过 `SELECT VERSION()` 测试连接。
- `SHOW DATABASES` 和通过 `USE` 切换数据库。
- 读取表、视图、例程、触发器、字段、索引和 DDL 元数据。
- 表数据分页查询，并支持筛选和排序。
- 行级 `INSERT`、`UPDATE` 和 `DELETE`；更新和删除会优先使用主键，没有主键时回退到
  NULL-safe 的整行条件匹配。
- 任意 SQL 执行和 `EXPLAIN`。
- 每个连接配置可单独控制 TLS。

## 导入导出说明

- 表数据导出的是当前已加载的结果，包括当前分页、筛选和排序，不是整张表全量导出。
- SQL 编辑器导出的是最近一次 SQL 查询结果；没有结果列的语句不提供导出。
- CSV 导出包含 UTF-8 BOM，方便包含中文或其他非 ASCII 文本时被表格软件正确识别。
- CSV 导入采用逐行插入，更适合小批量数据。
- 导入会自动跳过自增字段和二进制字段，支持按表头默认匹配字段，并可将空字符串按
  `NULL` 处理。

## 安全说明和限制

- 当前尚未实现 SSH Tunnel。建议通过 VPN、内网或测试数据库连接，不要将生产 MySQL
  直接暴露在公网。
- 部分写入和导入路径当前使用转义后的 SQL 字面量构造语句。后续建议升级为参数绑定以增强安全性。
- 高风险 SQL 二次确认可以降低误操作概率，但不能替代最小权限数据库账号和经过验证的备份。
- 只读连接配置会在 SQL 工作台和导入流程中阻止写入、修改和 DDL 语句。
- 当前 simple query 处理对受影响行数以摘要消息形式展示，尚未完整建模 MySQL affected rows。

## 路线图

- SSH Tunnel 支持。
- 批量或事务化 CSV 导入。
- 更强的导入字段类型校验。
- 新增、更新、删除和导入路径使用参数化查询。
- 更高级的表数据筛选和排序交互。


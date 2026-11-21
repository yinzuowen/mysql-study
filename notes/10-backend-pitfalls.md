# 第 10 章 后端开发常见坑 🟢

> 前面几章讲的是 MySQL 本身，这一章讲**写后端代码时最容易踩的坑**。它们大多不会让程序立刻报错，而是在数据量变大、并发变高、或者某个用户输入了奇怪的内容时才暴露：数据被拖库、接口越来越慢、金额对不上账、emoji 存不进去、时间差了 8 小时……
>
> 每个坑都按「错误写法 → 后果（实测）→ 正确写法」来讲。实验都在本机 MySQL 上跑过，用的是 `itcast.t_user` 和临时建的 `tmp_ch10_*` 表（实验完已删除）。

## 1. SQL 注入 🔴 最严重

### 错误写法：把用户输入直接拼进 SQL

```java
// 登录、搜索等接口里，name 来自用户输入
String sql = "select * from t_user where name = '" + name + "'";
```

正常输入 `吕布`，拼出来的 SQL 只查到 1 行。但如果用户输入：

```
' or '1'='1
```

拼出来的 SQL 变成：

```sql
select id, name, phone from t_user where name = '' or '1'='1';
```

### 后果（实测）

`'1'='1'` 永远为真，**返回了全部 24 行**，所有用户的手机号都泄露了。登录接口里，这样能不用密码直接登录；更恶意的输入还能拼出 `; drop table ...` 或者用 `union select` 读取其他表。

### 正确写法：预编译（参数化）

SQL 结构先固定下来，用户输入只作为**参数值**传进去，永远不会被当成 SQL 语法解析：

```java
// JDBC
PreparedStatement ps = conn.prepareStatement("select * from t_user where name = ?");
ps.setString(1, name);
```

在 MySQL 里用 `prepare` 模拟同样的过程：

```sql
prepare stmt from 'select id, name from t_user where name = ?';
set @n = ''' or ''1''=''1';    -- @n 的值就是 ' or '1'='1
execute stmt using @n;
```

实测：**返回空结果**。MySQL 把整个 `' or '1'='1` 当成一个普通字符串去匹配 `name`，没有用户叫这个名字。

### MyBatis：`#{}` 和 `${}`

| 写法 | 原理 | 安全吗 |
|---|---|---|
| `#{name}` | 预编译，生成 `?` 占位符 | ✅ 安全，**默认都用这个** |
| `${name}` | 直接把字符串拼进 SQL | ❌ 有注入风险 |

```xml
<!-- ✅ -->
<select id="findByName">select * from t_user where name = #{name}</select>

<!-- ❌ -->
<select id="findByName">select * from t_user where name = '${name}'</select>
```

### 特殊情况：动态排序字段

`order by` 后面的列名不能用 `?` 占位（占位符只能代表值，不能代表列名），很多人就改用 `${}`：

```xml
<!-- ❌ 前端传 sortField=id;drop table t_user 就出事了 -->
order by ${sortField}
```

正确做法是**白名单**：后端只接受预先定义好的几个值。

```java
private static final Set<String> SORT_FIELDS = Set.of("id", "age", "createtime");

String sortField = SORT_FIELDS.contains(req.getSortField()) ? req.getSortField() : "id";
String sortOrder = "desc".equalsIgnoreCase(req.getSortOrder()) ? "desc" : "asc";
```

## 2. N+1 查询

### 错误写法：在循环里查数据库

查 20 个订单，每个订单再查一次用户：

```java
List<Order> orders = orderMapper.list(pageSize);          // 1 次查询
for (Order o : orders) {
    User u = userMapper.findById(o.getUserId());          // N 次查询
    o.setUserName(u.getName());
}
```

### 后果

一页 20 条数据就要查 21 次数据库。每次查询都有网络往返（本机零点几毫秒，跨机房可能几毫秒），数据一多、接口一并发，数据库连接很快被占满。在 ORM（如 JPA/Hibernate 的懒加载）里，这种循环查询往往是**隐藏**的，看代码根本发现不了。

### 正确写法：用 `in` 批量查，或用 `join`

```sql
-- 先查订单，收集所有 user_id，再一次性查出来
select id, name from t_user where id in (1, 3, 5, 8, 13);
```

```java
Set<Long> userIds = orders.stream().map(Order::getUserId).collect(toSet());
Map<Long, User> userMap = userMapper.findByIds(userIds).stream()
        .collect(toMap(User::getId, u -> u));
orders.forEach(o -> o.setUserName(userMap.get(o.getUserId()).getName()));
```

无论多少条订单，都只查 2 次。也可以直接 `join`：

```sql
select o.*, u.name user_name from t_order o join t_user u on o.user_id = u.id where ...;
```

> 开发时打开 SQL 日志（MyBatis 的 `log-impl`、Hibernate 的 `show_sql`），看一个接口执行了多少条 SQL，是发现 N+1 最简单的办法。

## 3. `select *`

### 错误写法

```sql
select * from tmp_ch10_big where user_id = 42;
```

### 后果（实测）

在 100 万行的表上，`user_id` 有索引：

| SQL | Extra | 耗时 |
|---|---|---|
| `select * from tmp_ch10_big where user_id = 42` | `NULL`（要回表） | 约 1.08 ms |
| `select id, user_id from tmp_ch10_big where user_id = 42` | `Using index`（覆盖索引） | 约 0.09 ms |

`select *` 用不上覆盖索引，每一行都要回表；还会把 `content` 这种大字段也传给应用，浪费网络和内存。另外，表加了新字段后，`select *` 返回的列也会跟着变，可能让代码出错。

### 正确写法

只查需要的列：

```sql
select id, user_id, title from tmp_ch10_big where user_id = 42;
```

## 4. 深分页

### 错误写法

```sql
select id, title from tmp_ch10_big order by id limit 900000, 10;
```

### 后果（实测，100 万行）

| 写法 | 耗时 |
|---|---|
| `limit 0, 10`（第 1 页） | 约 0.012 s |
| `limit 900000, 10`（第 90001 页） | 第一次约 **1.59 s**，数据进缓存后约 0.34 s |

MySQL 要先读出前 900010 行，再丢掉前 900000 行，越往后翻越慢。

### 正确写法

**方式 1：子查询先在索引上定位 id**（实测约 0.24–0.28 s，比原来快，但仍要扫描索引）

```sql
select b.id, b.title from tmp_ch10_big b
join (select id from tmp_ch10_big order by id limit 900000, 10) t on b.id = t.id;
```

**方式 2：记住上一页最后一个 id（游标分页）**（实测约 **0.0002 s**）

```sql
select id, title from tmp_ch10_big where id > 900000 order by id limit 10;
```

游标分页最快，适合「加载更多」、无限滚动、后台批量导出。缺点是不能直接跳到第 N 页。产品上也可以限制最大页数，没人会真的翻到第 9 万页。

## 5. 大事务

### 错误写法

一个事务里删除或更新大量数据，或者在事务里调用远程接口：

```sql
begin;
delete from tmp_ch10_big where id <= 300000;
commit;
```

### 后果（实测）

删除 30 万行耗时约 **1.71 s**，期间这 30 万行全部被锁住；如果中途决定回滚，`rollback` 又花了约 **1.45 s**。数据量再大一个数量级，就是几十秒甚至几分钟的锁等待，主从复制也会明显延迟（从库要等整个事务传过去才能执行）。

### 正确写法：分批处理

```sql
delete from tmp_ch10_big where id <= 300000 limit 5000;   -- 实测约 0.03 s
-- 在代码里循环执行，直到影响行数为 0；每批之间可以 sleep 一下，给其他请求让路
```

事务里也不要调用 HTTP/RPC、发消息、做耗时计算，详见[第 5 章](05-transaction.md)。

## 6. 批量操作一次太多

### 错误写法

两个极端都是坑：

```java
// ❌ 一条一条插，10 万条就是 10 万次网络往返 + 10 万次提交
for (User u : users) { userMapper.insert(u); }

// ❌ 10 万条拼成一条 SQL
insert into t_user (...) values (...), (...), ... ;  -- 10 万组
```

### 后果

- 逐条插入：极慢。
- 一次全部插入：SQL 文本超过 `max_allowed_packet`（本机是 64 MB）直接报错；即使没超过，也是一个巨大的事务，锁多、undo log 大、出错就全部回滚。MyBatis 的 `<foreach>` 拼接过长 SQL 也会很慢。

### 正确写法：分批，每批几百到一千条

```java
for (List<User> batch : Lists.partition(users, 500)) {
    userMapper.batchInsert(batch);   // insert ... values (...), (...), ... 每次 500 条
}
```

JDBC 连接串加上 `rewriteBatchedStatements=true`，`addBatch()` / `executeBatch()` 才会真正合并成批量插入。

## 7. 金额用 `float` / `double`

### 错误写法

```sql
create table t_order (amount double);
```

### 后果（实测）

```sql
-- 存了 0.1 和 0.2 两条，求和
select sum(f), sum(d), sum(m) from tmp_ch10_money;
```

```
| sum(f)  float       | sum(d)  double      | sum(m)  decimal |
| 0.30000000447034836 | 0.30000000000000004 | 0.30            |
```

`sum(d) = 0.3` 的结果是 `0`（不相等）。更严重的是 `float` 只有约 7 位有效数字：存入 `12345678.91`，**读出来是 `12345700`**，直接丢了 21.09 元。

### 正确写法

```sql
amount decimal(10, 2) not null comment '金额，单位：元'
```

Java 里对应 `BigDecimal`，并且用 `new BigDecimal("0.1")` 或 `BigDecimal.valueOf(0.1)`，不要用 `new BigDecimal(0.1)`。另一种常见做法是用 `bigint` 存「分」。

## 8. 字符集用 `utf8` 存不了 emoji

### 错误写法

```sql
create table t_comment (content varchar(200)) default charset = utf8;   -- utf8 实际是 utf8mb3
```

### 后果（实测）

```sql
insert into tmp_ch10_utf8 values ('好评👍');
-- ERROR 1366 (HY000): Incorrect string value: '\xF0\x9F\x91\x8D' for column 'c' at row 1
```

MySQL 的 `utf8` 是阉割版（`utf8mb3`），每个字符最多 3 字节；emoji 要 4 字节，存不进去。用户评论里带个表情，接口就 500 了。

### 正确写法

```sql
default charset = utf8mb4
```

实测 `utf8mb4` 表能正常存入，`char_length('好评👍') = 3`（3 个字符），`length() = 10`（10 个字节）。数据库、表、连接串（`characterEncoding=UTF-8`）都要统一。

## 9. 时区

### 错误写法

应用服务器、数据库、JDBC 连接串的时区各不相同，或者混用 `timestamp` 和 `datetime` 却不清楚区别。

### 后果（实测）

同一时刻用 `now()` 插入一个 `datetime` 和一个 `timestamp` 字段，然后切换会话时区再查：

| 会话时区 | `now()` | `datetime` 字段 | `timestamp` 字段 |
|---|---|---|---|
| `+08:00`（插入时） | 2026-11-20 20:44:03 | 2026-11-20 20:44:03 | 2026-11-20 20:44:03 |
| `+00:00` | 2026-11-20 12:44:03 | 2026-11-20 **20:44:03** | 2026-11-20 **12:44:03** |

- `now()` 的结果受会话 `time_zone` 影响。
- `timestamp` 按 UTC 存储，**读出来会按当前时区转换**。
- `datetime` 存什么就是什么，不做转换。

再加上 JDBC 的 `serverTimezone` 配错，Java 拿到的时间就可能差 8 小时。另外 `timestamp` 最大只到 `2038-01-19 03:14:07`（UTC），实测插入 `2039-01-01` 报 `ERROR 1292: Incorrect datetime value`。

### 正确写法

- 业务时间字段用 `datetime`。
- 数据库服务器、应用服务器、连接串时区统一，如 `serverTimezone=Asia/Shanghai`。
- 跨时区业务：统一存 UTC，展示时再转成用户所在时区。

## 10. `null` 和空字符串

### 错误写法

字段允许 `null`，查询时又用 `=`、`!=`、`not in` 去比较。

### 后果（实测）

表里三行：`'小明'`、`''`（空字符串）、`null`。

| 查询 | 返回 |
|---|---|
| `count(*)` / `count(nickname)` | 3 / **2**（`null` 不计数） |
| `where nickname = ''` | 只有空字符串那行 |
| `where nickname = null` | **空**（任何值和 `null` 比较结果都是 `null`，不是真） |
| `where nickname is null` | 只有 `null` 那行 |
| `where nickname != '小明'` | **只有空字符串那行，`null` 那行丢了** |
| `where nickname not in ('小明', null)` | **空**，一行都没有 |
| `concat('昵称：', nickname)`（`null` 那行） | `NULL`，整个结果变成 `null` |

### 正确写法

- 建表时尽量 `not null default ''` 或 `not null default 0`，从源头避免 `null`。
- 判断 `null` 只能用 `is null` / `is not null`。
- 两种都要查时写全：`where nickname is null or nickname = ''`。
- `not in` 的子查询结果里可能有 `null` 时，改用 `not exists`。

## 11. 隐式类型转换

### 错误写法：字符串列和数字比较

```sql
-- code 是 varchar，有索引
select id, code from tmp_ch10_conv where code = 1;
```

### 后果（实测）

表里有 `'1'`、`'001'`、`'1abc'`、`'1.0'`、`'2'` 五行：

| 查询 | 返回 | type |
|---|---|---|
| `where code = 1` | `'001'`、`'1'`、`'1.0'`、`'1abc'` **4 行** | `index`（扫描整个索引） |
| `where code = '1'` | 只有 `'1'` 1 行 | `ref` |

字符串和数字比较时，MySQL 把**每一行的字符串转成数字**再比，`'001'`、`'1.0'`、`'1abc'` 都转成了 1。结果错了，而且因为要对每行做转换，索引没法正常使用。`t_user` 上也一样：`where phone = 17799990000` 是 `type=ALL` 全表扫描，`where phone = '17799990000'` 是 `type=const`。

反过来，数字列和字符串比较：`where id = '1abc'` 实测返回 `id = 1` 的那行（只产生一个 warning）。

### 正确写法

- 参数类型和列类型保持一致：`varchar` 列传字符串，数字列传数字。
- Java 里实体类字段类型和数据库列类型一致（`phone` 用 `String` 不要用 `Long`）。
- 手机号、订单号、身份证号这类「看起来像数字」的编号，用字符串类型存。

## 12. 大小写和尾随空格

### 错误写法

以为 `where username = 'tom'` 是精确匹配。

### 后果（实测）

本机默认排序规则是 `utf8mb4_0900_ai_ci`（`ci` = case insensitive，不区分大小写；`ai` = accent insensitive，不区分重音）：

| 比较 | 结果 |
|---|---|
| `'a' = 'A'` | 1（相等） |
| `'é' = 'e'` | 1（相等） |
| `'a' = 'a '`（尾随空格） | 0（`0900` 系列不忽略尾随空格） |
| `'a' = 'a ' collate utf8mb4_general_ci` | **1**（旧的 `general_ci` 忽略尾随空格） |

- 表里有用户 `Tom`，查 `where username = 'tom'` **能查到**。
- `username` 有唯一索引时，再注册 `TOM` 会报 `ERROR 1062: Duplicate entry 'TOM'`。
- 老项目用 `utf8mb4_general_ci` 时，`'tom'` 和 `'tom '` 也会被当成同一个值。

### 正确写法

- 需要区分大小写的列（如区分大小写的账号、邀请码、文件名），单独指定 `collate utf8mb4_bin`。实测改成 `utf8mb4_bin` 后，`Tom` 和 `TOM` 可以同时存在。
- 临时区分大小写查询：`where username collate utf8mb4_bin = 'tom'`。
- 用户输入在进数据库前统一 `trim()`。

## 13. `update` / `delete` 前不先 `select`

### 错误写法

```sql
update t_user set status = '0';                 -- 忘了写 where，全表都改了
delete from t_user where name like '%张%';      -- 条件写宽了
```

### 后果

改错的数据很难恢复，只能从备份或 binlog 里找。

### 正确写法

1. 先用**同样的 `where`** 写一条 `select`，看看影响哪些行、多少行：
   ```sql
   select count(*) from t_user where profession = '软件工程' and status = '1';
   ```
2. 确认无误再把 `select` 改成 `update` / `delete`。
3. 手动执行时放进事务，检查影响行数再提交：
   ```sql
   begin;
   update t_user set status = '0' where profession = '软件工程' and status = '1';
   -- 看提示的 Rows matched / Changed 是否符合预期
   commit;   -- 不对就 rollback
   ```
4. 客户端可以开启安全模式 `set sql_safe_updates = 1;`：没有带索引条件的 `where` 或 `limit` 的 `update`/`delete` 会被拒绝执行。

## 14. 生产环境改数据的流程

不要直接连生产库手动改，一般流程是：

1. **写 SQL 脚本**，包含：改之前的 `select`（记录原值）、修改语句、改之后的校验 `select`。
2. **准备回滚脚本**：把原值改回去的 SQL。
3. **在测试环境执行一遍**。
4. **提交审核**（大部分公司用 DMS、Archery、Yearning 这类工单平台）。
5. **执行前备份**受影响的数据：`create table t_user_bak_20261120 as select * from t_user where ...;`
6. 大批量修改**分批执行**，放在业务低峰期。
7. 执行后用校验 SQL 核对结果。

## 15. 连接池参数

后端应用通过连接池（Spring Boot 默认 HikariCP）访问数据库。常见配置：

```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/itcast?useUnicode=true&characterEncoding=UTF-8&serverTimezone=Asia/Shanghai&rewriteBatchedStatements=true
    hikari:
      maximum-pool-size: 10       # 最大连接数，默认 10
      minimum-idle: 10            # 最小空闲连接数
      connection-timeout: 30000   # 拿不到连接时最多等 30 秒，默认 30000 ms
      max-lifetime: 1800000       # 连接最长存活 30 分钟，要小于 MySQL 的 wait_timeout
```

常见坑：

| 坑 | 现象 | 做法 |
|---|---|---|
| 连接数开得特别大 | 数据库总连接数超过 `max_connections`（本机 151），报 `Too many connections` | 连接数不是越大越好，几十个通常够用；所有应用实例的连接数加起来要小于 `max_connections` |
| 慢 SQL、长事务占着连接不还 | 连接池耗尽，报 `Connection is not available, request timed out after 30000ms` | 先优化慢 SQL，缩短事务 |
| `max-lifetime` 大于 `wait_timeout` | MySQL 已断开空闲连接（本机 `wait_timeout` 是 28800 秒），应用拿到失效连接报错 | `max-lifetime` 比 `wait_timeout` 小一些 |

## 16. 没有慢查询监控

### 错误做法

上线后不知道哪些 SQL 慢，等用户投诉才去查。

### 正确做法

- 开启慢查询日志（见 [04-performance.sql](../practice/04-performance.sql)）。本机 `slow_query_log = 1`，但 `long_query_time` 是默认的 **10 秒**，对接口来说太宽松，一般设成 1 秒甚至更低。
- 定期用 `mysqldumpslow` 或 `pt-query-digest` 汇总慢日志，找出最慢、执行最多的 SQL。
- 应用侧记录 SQL 耗时（如 MyBatis 拦截器、APM 工具 SkyWalking），超过阈值就告警。
- 新写的 SQL 上线前先用 `explain` 检查。

## 17. 逻辑删除的坑

逻辑删除：不真正 `delete`，而是 `update ... set is_deleted = 1`。

### 坑 1：查询时忘了加条件

实测：表里两个用户，删除了 `tom`（`is_deleted = 1`）：

| 查询 | 结果 |
|---|---|
| `select count(*) from tmp_ch10_soft` | **2**（把已删除的也算进去了） |
| `select count(*) from tmp_ch10_soft where is_deleted = 0` | 1 |

每条查询、每个 `join` 都要记得加 `is_deleted = 0`，手写 SQL 很容易漏。MyBatis-Plus 的 `@TableLogic` 可以自动加上这个条件（但手写的 XML SQL 仍要自己加）。

### 坑 2：唯一索引冲突

`username` 有唯一索引。逻辑删除 `tom` 后，新用户再注册 `tom`：

```
ERROR 1062 (23000): Duplicate entry 'tom' for key 'tmp_ch10_soft.uk_username'
```

已删除的记录还占着这个用户名。

### 正确写法

加一个 `delete_token` 字段：未删除时为 0，删除时设为自己的 `id`（或删除时间戳），唯一索引建在 `(username, delete_token)` 上：

```sql
alter table tmp_ch10_soft
    add column delete_token bigint not null default 0,
    drop index uk_username,
    add unique key uk_username (username, delete_token);

update tmp_ch10_soft set is_deleted = 1, delete_token = id where username = 'tom';
```

实测之后再插入 `tom` 成功：

```
| id | username | is_deleted | delete_token |
|  1 | tom      |          1 |            1 |   <- 已删除的
|  2 | jerry    |          0 |            0 |
|  4 | tom      |          0 |            0 |   <- 新注册的
```

## 18. 小结

| 坑 | 一句话 |
|---|---|
| SQL 注入 | 只用预编译参数，MyBatis 用 `#{}`；动态列名用白名单 |
| N+1 | 不在循环里查库，用 `in` 或 `join` |
| `select *` | 只查需要的列 |
| 深分页 | 用游标分页 `where id > ? limit n` |
| 大事务 | 分批处理，事务里不调远程接口 |
| 批量操作 | 每批几百到一千条，加 `rewriteBatchedStatements=true` |
| 金额 | `decimal` / `BigDecimal`，或 `bigint` 存分 |
| 字符集 | `utf8mb4` |
| 时区 | 用 `datetime`，各处时区统一 |
| `null` | 尽量 `not null`，判断用 `is null` |
| 类型转换 | 参数类型和列类型一致 |
| 大小写 | 默认不区分大小写，需要区分用 `utf8mb4_bin` |
| 改数据 | 先 `select`，放事务里，走审核流程 |
| 连接池 | 连接数适中，`max-lifetime` < `wait_timeout` |
| 慢查询 | 开慢查询日志，`long_query_time` 调到 1 秒左右 |
| 逻辑删除 | 查询别忘 `is_deleted = 0`，唯一索引加 `delete_token` |

---

上一章：[锁 🟡](09-lock.md) · [目录](../README.md) · 下一章：[原理与运维 ⚪ / 🟡](11-internals-and-ops.md)

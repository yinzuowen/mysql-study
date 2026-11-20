# 第 11 章 原理与运维 ⚪ / 🟡

> **为什么要学**：前面的章节讲「怎么用」，这一章讲「为什么能这样用」，以及数据库在生产环境里怎么部署和维护。
> 写业务时会遇到的问题，答案很多在这里：为什么 `commit` 之后宕机数据也不会丢？为什么可重复读级别下，别人提交的修改我看不到？为什么刚写进去的数据马上查却查不到（主从延迟）？误删了数据怎么恢复？
>
> 入门阶段先看懂 **MVCC、三种日志、备份恢复**（面试和排查问题最常用，标 🟡），视图、存储过程、主从、分库分表知道是什么即可（标 ⚪）。
>
> 本章的实验在本机 MySQL（版本 26.10，默认隔离级别 Repeatable Read，binlog 已开启）上实际跑过，用的是 `tmp_ch11_*` 临时表，做完已全部删除。**主从复制和分库分表需要多台数据库，没有在本机实测**，只讲原理。

## 1. InnoDB 内部结构概览

```
                         ┌──────────────── 内存 ────────────────┐
  SQL 读写 ─────────────▶│  Buffer Pool  缓存数据页、索引页        │
                         │    ├─ Change Buffer  缓存二级索引的修改 │
                         │    └─ 自适应哈希索引（可选）             │
                         │  Log Buffer   redo log 的内存缓冲       │
                         └───────┬──────────────────────┬────────┘
                                 │ 后台线程刷脏页          │ 事务提交时写入
                         ┌───────▼────────── 磁盘 ───────▼────────┐
                         │  表空间 .ibd（数据和索引）               │
                         │  undo 表空间 undo_001 / undo_002        │
                         │  redo log  #innodb_redo/                │
                         └─────────────────────────────────────────┘
```

| 组件 | 作用 |
|---|---|
| Buffer Pool | 缓存磁盘上的页，读写都先在这里进行，详见[第 6 章](06-storage-engine.md) |
| Change Buffer | 修改二级索引时，如果对应的页不在内存里，先把修改记下来，等这个页被读进内存时再合并，减少随机磁盘 IO。唯一索引用不上（要读页判断是否重复） |
| 自适应哈希索引 | InnoDB 发现某些索引值被频繁访问时，自动建 hash 索引加速。本机 `innodb_adaptive_hash_index = 0`，默认关闭 |
| Log Buffer | redo log 先写到这里，再刷到磁盘，默认 64MB |

本机相关参数实测：

```sql
select @@innodb_log_buffer_size / 1024 / 1024 as log_buffer_mb,     -- 64
       @@innodb_redo_log_capacity / 1024 / 1024 as redo_mb,         -- 100
       @@innodb_change_buffering,                                   -- all
       @@innodb_adaptive_hash_index;                                -- 0
```

## 2. 三种日志 🟡

| 日志 | 属于 | 记录什么 | 主要用途 |
|---|---|---|---|
| redo log | InnoDB | 「某个页的某个位置改成了什么」（物理日志） | 崩溃恢复，保证**持久性** |
| undo log | InnoDB | 「怎么把修改撤销回去」（逻辑日志） | 回滚，保证**原子性**；MVCC |
| binlog | 服务层 | 所有修改数据的操作 | 主从复制、按时间点恢复数据 |

### 2.1 redo log：为什么 commit 之后宕机数据不丢

问题：修改先发生在 Buffer Pool 的页里，如果每次 `commit` 都把整个 16KB 的页刷回磁盘，太慢了（随机写，而且一页里可能只改了几个字节）。如果不刷，宕机时内存里的修改就丢了。

解决：**WAL（Write-Ahead Logging，先写日志）**。

```
事务修改数据
  │
  ├─ 1. 修改 Buffer Pool 里的页（变成脏页）
  ├─ 2. 把「改了什么」写进 redo log buffer
  │
commit
  └─ 3. 把 redo log 刷到磁盘（顺序写，很快）   ← 到这一步就算提交成功
     4. 脏页稍后由后台线程慢慢刷回 .ibd       ← 不在 commit 的关键路径上

宕机重启 → 用 redo log 把还没刷盘的修改重新做一遍 → 数据恢复
```

redo log 是**顺序写**（追加在文件末尾），比随机写数据页快得多。它的空间是循环使用的，对应的脏页刷盘之后，那部分 redo log 就可以被覆盖。

`innodb_flush_log_at_trx_commit` 控制 commit 时 redo log 怎么刷盘：

| 值 | commit 时 | 宕机可能丢多少 | 性能 |
|---|---|---|---|
| **1（默认）** | 每次都写入并刷到磁盘 | 不丢 | 最慢 |
| 0 | 不写，后台线程每秒写入并刷盘一次 | MySQL 进程崩溃就可能丢约 1 秒的事务 | 最快 |
| 2 | 写到操作系统缓存，每秒刷盘一次 | MySQL 崩溃不丢，**操作系统崩溃或断电**可能丢约 1 秒 | 中间 |

```sql
select @@innodb_flush_log_at_trx_commit;   -- 本机：1
```

涉及钱的业务必须用 1。

### 2.2 undo log：回滚和旧版本

每次修改数据前，InnoDB 先在 undo log 里记下**怎么撤销**：

| 操作 | undo log 记录 |
|---|---|
| `insert` 一行 | 回滚时把它删掉 |
| `delete` 一行 | 回滚时把它插回来 |
| `update` 一行 | 回滚时把旧值改回去 |

两个作用：

1. **回滚**：执行 `rollback` 或事务出错时，按 undo log 把修改撤销。
2. **MVCC**：同一行的多个旧版本通过 undo log 串成**版本链**，别的事务可以读到旧版本（见下一节）。

本机的 undo 表空间：

```sql
select tablespace_name, file_name from information_schema.files where file_type = 'UNDO LOG';
```
```
| innodb_undo_001 | ./undo_001 |
| innodb_undo_002 | ./undo_002 |
```

> 长事务会让 undo log 一直不能清理（还有人可能要读旧版本），导致 undo 空间越来越大。这是「事务要小」的又一个原因。

### 2.3 binlog：复制和恢复的基础

binlog 是 MySQL 服务层的日志，**所有存储引擎都会写**，记录所有修改数据和表结构的操作（`select` 不记录）。

```sql
select @@log_bin, @@binlog_format, @@sync_binlog;   -- 本机：1、ROW、1
show binary logs;                                    -- 列出所有 binlog 文件
```
```
+---------------+-----------+-----------+
| Log_name      | File_size | Encrypted |
+---------------+-----------+-----------+
| binlog.000001 |     33618 | No        |
| binlog.000002 |     25745 | No        |
+---------------+-----------+-----------+
```

**三种格式**：

| 格式 | 记录什么 | 优点 | 缺点 |
|---|---|---|---|
| statement | 原始 SQL 语句 | 日志小 | `now()`、`uuid()` 这类函数在从库重放结果可能不一样 |
| **row（默认）** | 每一行修改前后的值 | 准确，可以用来恢复数据 | 一条 SQL 改 10 万行，就记 10 万行，日志大 |
| mixed | 一般用 statement，可能不一致时自动切换成 row | 折中 | |

**实测**：建一张临时表，插入一行、更新一行，再看 binlog：

```sql
create table tmp_ch11_bin (id int primary key, money int);
insert into tmp_ch11_bin values (1, 100);
update tmp_ch11_bin set money = 200 where id = 1;

show binlog events in 'binlog.000002' from 27957;
```
```
| Pos   | Event_type  | Info                                                                  |
| 27957 | Gtid        | SET @@SESSION.GTID_NEXT= 'f5c3c094-...:176'                           |
| 28034 | Query       | use `itcast`; create table tmp_ch11_bin (id int primary key, ...)    |
| 28183 | Gtid        | SET @@SESSION.GTID_NEXT= 'f5c3c094-...:177'                           |
| 28262 | Query       | BEGIN                                                                 |
| 28339 | Table_map   | table_id: 140 (itcast.tmp_ch11_bin)                                   |
| 28400 | Write_rows  | table_id: 140 flags: STMT_END_F                                       |   <- insert
| 28444 | Xid         | COMMIT /* xid=4036 */                                                 |
| ...   |             |                                                                       |
| 28701 | Update_rows | table_id: 140 flags: STMT_END_F                                       |   <- update
| 28755 | Xid         | COMMIT /* xid=4037 */                                                 |
```

row 格式下 `Info` 里看不到具体数据，要用 `mysqlbinlog` 工具解析：

```bash
mysqlbinlog -v --base64-output=decode-rows --start-position=27957 /opt/homebrew/var/mysql/binlog.000002
```
```
### UPDATE `itcast`.`tmp_ch11_bin`
### WHERE
###   @1=1
###   @2=100        <- 修改前
### SET
###   @1=1
###   @2=200        <- 修改后
```

因为 row 格式记录了修改前后的完整数据，误删、误改后可以据此把数据找回来（见第 6 节）。

### 2.4 两阶段提交：redo log 和 binlog 要一致

一个事务提交时，redo log 和 binlog 都要写。如果只写成功了一个就宕机：

- redo log 有、binlog 没有：主库重启后有这条数据，从库没有 → **主从不一致**。
- binlog 有、redo log 没有：主库重启后没有这条数据，从库有 → 也不一致。

所以 InnoDB 用**两阶段提交**：

```
1. prepare 阶段：写 redo log，标记为 prepare
2. 写 binlog
3. commit 阶段：把 redo log 标记为 commit

宕机重启时检查：
  redo log 是 commit             → 提交
  redo log 是 prepare，binlog 完整 → 提交
  redo log 是 prepare，binlog 不完整 → 回滚
```

`innodb_flush_log_at_trx_commit = 1` 加上 `sync_binlog = 1`（每次提交都把 binlog 刷盘）俗称「**双 1 配置**」，是保证数据不丢的标准配置。本机两个都是 1。

## 3. MVCC 🟡 面试高频

MVCC（Multi-Version Concurrency Control，多版本并发控制）：**同一行数据保留多个版本，读的时候根据规则选一个合适的版本**。好处是普通 `select` 不用加锁，读写互不阻塞。

### 3.1 当前读和快照读

| | 快照读 | 当前读 |
|---|---|---|
| 语句 | 普通 `select` | `select ... for update`、`for share`、`insert`、`update`、`delete` |
| 读到什么 | 某个时间点的版本（可能是旧的） | 最新已提交的版本，并且加锁 |
| 靠什么实现 | MVCC | 锁（见[第 9 章](09-lock.md)） |

### 3.2 实现原理一：隐藏字段

InnoDB 的每一行除了你定义的列，还有隐藏字段：

| 隐藏字段 | 含义 |
|---|---|
| `DB_TRX_ID` | 最后一次修改这一行的事务 id |
| `DB_ROLL_PTR` | 回滚指针，指向 undo log 里这一行的上一个版本 |
| `DB_ROW_ID` | 表没有主键时，InnoDB 自动生成的行 id |

### 3.3 实现原理二：undo log 版本链

假设 `id = 1` 这一行先后被事务 10、20、30 修改，每次修改都把旧版本放进 undo log，用 `DB_ROLL_PTR` 串起来：

```
 当前记录（在表里）
┌────┬───────┬───────────┬─────────────┐
│ id │ money │ DB_TRX_ID │ DB_ROLL_PTR │
│ 1  │  400  │    30     │      ───────┼──┐
└────┴───────┴───────────┴─────────────┘  │
                                          ▼  undo log
                     ┌────┬───────┬───────────┬─────────────┐
                     │ 1  │  300  │    20     │      ───────┼──┐
                     └────┴───────┴───────────┴─────────────┘  │
                                                               ▼
                                          ┌────┬───────┬───────────┬─────────────┐
                                          │ 1  │  200  │    10     │    NULL     │
                                          └────┴───────┴───────────┴─────────────┘
```

### 3.4 实现原理三：ReadView

快照读时会生成一个 **ReadView**，用来判断版本链上的哪个版本「我能看到」。它有四个字段：

| 字段 | 含义 |
|---|---|
| `m_ids` | 生成 ReadView 时，**还没提交**的活跃事务 id 列表 |
| `min_trx_id` | `m_ids` 里最小的 id |
| `max_trx_id` | 下一个将要分配的事务 id（当前最大 id + 1） |
| `creator_trx_id` | 创建这个 ReadView 的事务自己的 id |

从版本链的最新版本开始，拿它的 `DB_TRX_ID`（记为 `trx_id`）判断：

| 条件 | 能否看到 | 原因 |
|---|---|---|
| `trx_id == creator_trx_id` | ✅ | 自己改的 |
| `trx_id < min_trx_id` | ✅ | 生成 ReadView 前就已经提交了 |
| `trx_id >= max_trx_id` | ❌ | 生成 ReadView 之后才开启的事务改的 |
| `min_trx_id <= trx_id < max_trx_id` | 在 `m_ids` 里 ❌，不在 ✅ | 在就说明还没提交 |

看不到就顺着 `DB_ROLL_PTR` 找上一个版本，继续判断，直到找到能看到的版本。

### 3.5 RC 和 RR 的区别：ReadView 什么时候生成

| 隔离级别 | ReadView 生成时机 | 效果 |
|---|---|---|
| Read Committed | **每次**快照读都生成新的 | 能读到别人新提交的数据 → 不可重复读 |
| Repeatable Read | 事务里**第一次**快照读时生成，之后一直复用 | 整个事务看到的都是同一个快照 → 可重复读 |

### 3.6 实测

`tmp_ch11_bin` 里 `id = 1` 的 `money` 初始为 200。会话 A 读两次，中间会话 B 把它改成 300 并提交：

| 时间 | 会话 A | 会话 B |
|---|---|---|
| 1 | `begin;`<br>`select money ... where id = 1;` | |
| 2 | | `update tmp_ch11_bin set money = 300 where id = 1;`（自动提交） |
| 3 | `select money ... where id = 1;` | |
| 4 | `select money ... where id = 1 for update;` | |

实测结果：

| 会话 A 的读 | Repeatable Read | Read Committed |
|---|---|---|
| 第 1 次快照读 | 200 | 200 |
| 第 2 次快照读 | **200**（复用第一次的 ReadView） | **300**（生成了新的 ReadView） |
| `for update` 当前读 | **300** | 300 |

注意 RR 下的最后一行：同一个事务里，快照读是 200，当前读却是 300。所以在 RR 下「先 `select` 查出来，再根据查到的值去 `update`」是不安全的，要么用 `select ... for update`，要么把判断写进 `update` 的 `where` 条件（见[第 9 章](09-lock.md)「乐观锁与悲观锁」）。

## 4. 视图、存储过程、函数、触发器 ⚪

这些对象的逻辑都写在数据库里。互联网业务**一般不用**（视图偶尔用），原因：

- 业务逻辑分散在代码和数据库两个地方，难维护、难排查。
- 不好做版本管理、代码评审、单元测试。
- 数据库最难水平扩展，把计算压力放在数据库上不划算。
- 分库分表后基本没法用。

但你需要能看懂老项目里的这些代码。

### 4.1 视图

视图是一条保存起来的 `select`，用起来像一张表，但**不存数据**。

```sql
create view tmp_ch11_v_young as
select id, name, age from tmp_ch11_emp where age < 25
with check option;

select * from tmp_ch11_v_young;
```
```
+----+--------+------+
| id | name   | age  |
+----+--------+------+
|  1 | 张三   |   20 |
|  3 | 王五   |   22 |
+----+--------+------+
```

`with check option`：通过视图插入或修改的数据，必须满足视图的 `where` 条件：

```sql
insert into tmp_ch11_v_young (name, age) values ('赵六', 30);
-- ERROR 1369 (HY000): CHECK OPTION failed 'itcast.tmp_ch11_v_young'

update tmp_ch11_v_young set age = 26 where name = '张三';
-- ERROR 1369 (HY000): CHECK OPTION failed 'itcast.tmp_ch11_v_young'
```

用途：把复杂查询封装起来；只把部分列开放给别的系统或报表账号（权限控制）。

### 4.2 存储过程

一组 SQL 的集合，可以带参数、变量、条件判断和循环。在命令行里创建时要用 `delimiter` 临时改掉语句结束符，否则过程体里的 `;` 会被当成语句结束：

```sql
delimiter $$
create procedure tmp_ch11_p_count(in p_prof varchar(20), out p_cnt int)
begin
  select count(*) into p_cnt from t_user where profession = p_prof;
end$$
delimiter ;

call tmp_ch11_p_count('软件工程', @cnt);
select @cnt;   -- 4
```

### 4.3 函数

和存储过程类似，但**必须有返回值**，可以直接在 SQL 里调用：

```sql
delimiter $$
create function tmp_ch11_f_level(p_age int) returns varchar(10) deterministic
begin
  if p_age < 25 then return '青年';
  elseif p_age < 40 then return '中年';
  else return '资深';
  end if;
end$$
delimiter ;

select name, age, tmp_ch11_f_level(age) lvl from t_user where id <= 4;
```
```
+-----------+------+--------+
| name      | age  | lvl    |
+-----------+------+--------+
| 吕布      |   23 | 青年   |
| 曹操      |   33 | 中年   |
| 赵云      |   34 | 中年   |
| 孙悟空    |   54 | 资深   |
+-----------+------+--------+
```

### 4.4 触发器

在 `insert`、`update`、`delete` 之前或之后**自动执行**的 SQL。`old` 表示修改前的行，`new` 表示修改后的行：

```sql
delimiter $$
create trigger tmp_ch11_tg_emp_update after update on tmp_ch11_emp for each row
begin
  insert into tmp_ch11_log (op, row_id, detail)
  values ('update', new.id, concat('age: ', old.age, ' -> ', new.age));
end$$
delimiter ;

update tmp_ch11_emp set age = 31 where name = '李四';
select id, op, row_id, detail from tmp_ch11_log;
```
```
+----+--------+--------+---------------+
| id | op     | row_id | detail        |
+----+--------+--------+---------------+
|  1 | update |      2 | age: 30 -> 31 |
+----+--------+--------+---------------+
```

触发器是「隐形」的逻辑：看代码完全不知道改一行数据还会顺带写另一张表，排查问题时很容易被坑。操作日志这类需求，一般在代码里写，或者订阅 binlog（如 Canal）来做。

## 5. 主从复制与读写分离 ⚪（未在本机实测）

### 5.1 为什么要主从

- **读写分离**：主库负责写，多个从库分担读，提高读性能。
- **高可用**：主库挂了，可以把一个从库提升为新主库。
- **备份**：在从库上做备份，不影响主库。

### 5.2 原理

```
          主库 Master                                   从库 Slave
┌──────────────────────────┐                ┌──────────────────────────────┐
│ 事务提交                   │                │                              │
│   │                       │   网络传输      │  IO 线程                      │
│   ▼                       │ ─────────────▶ │   │ 把 binlog 写进 relay log   │
│ binlog ── dump 线程 ───────┼────────────────┼──▶ relay log（中继日志）        │
│                           │                │   │                          │
└──────────────────────────┘                │  SQL 线程                      │
                                            │   │ 读 relay log，重放到从库    │
                                            │   ▼                          │
                                            │ 从库数据                       │
                                            └──────────────────────────────┘
```

1. 主库把修改写进 binlog。
2. 从库的 **IO 线程**连上主库，把 binlog 拉过来，写进自己的 **relay log**（中继日志）。
3. 从库的 **SQL 线程**读 relay log，把修改重放一遍。

所以开启主从的前提是主库打开 binlog，并且每台机器的 `server_id` 不同。

### 5.3 复制延迟：写完马上读，读不到

复制是**异步**的，从库总会比主库慢一点（通常毫秒级，主库压力大或有大事务时可能到秒级、分钟级）。典型问题：

```
用户注册 → 写主库成功 → 跳转到个人主页 → 读从库 → 从库还没同步 → 「用户不存在」
```

常见解决办法：

- 写完马上要读的场景（注册后看主页、下单后看订单），**强制读主库**。
- 对一致性要求高的查询，一律走主库。
- 监控从库延迟：在从库上执行 `show replica status`，看 `Seconds_Behind_Source`。

读写分离一般用中间件或框架实现，比如 ShardingSphere、MyCat，或者 Spring 里配置多数据源，按 `@Transactional(readOnly = true)` 之类的规则路由。

## 6. 分库分表 ⚪（未在本机实测）

### 6.1 什么时候需要

单库单表的瓶颈：

- **数据量**：单表数据量很大（经验值千万级以上）时，索引变深、查询变慢，加列加索引也很痛苦。
- **并发**：单台数据库的连接数、CPU、磁盘 IO 都有上限。

**能不拆就不拆**。先做：加索引、优化 SQL、加缓存、读写分离、归档历史数据。都不够了再分库分表。

### 6.2 拆分方式

| 方式 | 怎么拆 | 例子 |
|---|---|---|
| 垂直分库 | 按业务拆成多个库 | 用户库、订单库、商品库（微服务每个服务一个库） |
| 垂直分表 | 一张表的列拆成多张表 | 商品基本信息表 + 商品详情表（大字段单独放） |
| 水平分库 | 同一张表的**行**分到多个库 | 订单表按 `user_id` 分到 4 个库 |
| 水平分表 | 同一张表的行分到同一个库的多张表 | `t_order_0` ~ `t_order_15` |

### 6.3 分片键怎么选

水平拆分时要选一个**分片键**，决定一行数据放到哪个库哪个表。比如 `user_id % 16` 决定订单放到哪张表。

- 选**最常用的查询条件**：订单最常按用户查，就按 `user_id` 分，这样查「我的订单」只查一张表。
- 数据要**分布均匀**，避免某个分片特别大（数据倾斜）。
- 不带分片键的查询要扫所有分片，非常慢。

### 6.4 带来的问题

| 问题 | 说明 | 常见做法 |
|---|---|---|
| 跨库 join | 两张表在不同库里，没法直接 `join` | 在代码里分两次查再组装；冗余字段；全局表（小表每个库都存一份） |
| 分布式事务 | 一个事务改了多个库，本地事务保证不了 | 尽量避免；用 Seata 等框架；最终一致性（消息队列） |
| 全局唯一 ID | 每张表自增会重复 | 雪花算法（Snowflake）、号段模式、Redis 自增 |
| 分页、排序、聚合 | 要从每个分片取数据再合并 | 中间件帮你做，但深分页代价很大 |
| 扩容 | 分片数改了，数据要重新分布 | 一开始预留足够的分片；一致性哈希 |

常用中间件：**ShardingSphere**（ShardingSphere-JDBC 以 jar 包的形式嵌在应用里，Java 项目最常用）、**MyCat**（独立部署的代理服务）。

## 7. 备份与恢复 🟡

### 7.1 mysqldump 逻辑备份

```bash
# 备份一个库（InnoDB 一定要加 --single-transaction，不锁表）
mysqldump --single-transaction -uroot -p itcast > itcast.sql

# 只备份一张表
mysqldump --single-transaction -uroot -p itcast t_user > t_user.sql

# 只备份表结构，不要数据
mysqldump --no-data -uroot -p itcast > itcast_schema.sql

# 恢复
mysql -uroot -p itcast < itcast.sql
```

`--single-transaction` 的原理：在一个可重复读事务里导出，靠 MVCC 读一致的快照，备份期间业务可以正常读写（见[第 9 章](09-lock.md)「全局锁」）。

### 7.2 用 binlog 按时间点恢复

场景：每天凌晨 3 点全量备份，今天下午 2 点有人误执行了 `delete from t_order`（忘了写 `where`）。

```
凌晨 3:00 全量备份 ──────── 正常的业务修改 ──────── 14:00 误删 ──── 现在
      │                                              │
      └──── 1. 先恢复全量备份                          │
            2. 用 binlog 重放 3:00 → 13:59:59 的修改 ──┘  跳过误删那条
```

```bash
# 1. 恢复凌晨的全量备份（到一个新库里，别直接覆盖线上）
mysql -uroot -p itcast_restore < backup_0300.sql

# 2. 找到误删语句在 binlog 里的位置
mysqlbinlog -v --base64-output=decode-rows binlog.000002 | grep -n -B5 'DELETE FROM `itcast`.`t_order`'

# 3. 重放全量备份之后、误删之前的 binlog
mysqlbinlog --start-datetime="2026-11-20 03:00:00" --stop-position=误删语句的位置 binlog.000002 | mysql -uroot -p itcast_restore
```

前提：binlog 是开着的，并且保留得够久（`binlog_expire_logs_seconds`）。所以生产环境一定要开 binlog、定期全量备份，并且**定期演练恢复**，确认备份真的能用。

> 线上数据量大时，逻辑备份太慢，一般用物理备份工具（如 Percona XtraBackup）或者云数据库自带的备份。

## 8. 常用运维命令 🟡

### 8.1 看当前有哪些连接在干什么

```sql
show processlist;          -- 或 show full processlist 显示完整 SQL
```

本机实测（节选）：

```
+-----+------+--------+---------+------+-----------+-----------------------------+
| id  | user | db     | command | time | state     | info                        |
+-----+------+--------+---------+------+-----------+-----------------------------+
|  18 | root | itcast | Sleep   |   24 |           | NULL                        |
| 237 | root | itcast | Query   |    0 | executing | select id, user, db, ...    |
+-----+------+--------+---------+------+-----------+-----------------------------+
```

- `command = Sleep`：空闲连接。
- `time`：当前状态持续了多少秒。一条 `Query` 的 `time` 很大，就是慢 SQL。
- `state`：常见的有 `executing`、`Sending data`、`Waiting for table metadata lock`（被 MDL 卡住，见第 9 章）。

### 8.2 杀掉卡住的连接

```sql
kill 237;          -- 断开 id 为 237 的连接，它未提交的事务会回滚
kill query 237;    -- 只终止它正在执行的 SQL，连接保留
```

先确认是谁的连接、在干什么，再 kill。kill 一个跑了很久的大事务，回滚也要花很长时间。

### 8.3 连接数和运行状态

```sql
select @@max_connections, @@wait_timeout;

show global status where variable_name in (
  'Threads_connected', 'Threads_running', 'Max_used_connections',
  'Uptime', 'Questions', 'Slow_queries');
```

本机实测：

```
| @@max_connections | @@wait_timeout |
|               151 |          28800 |

| Max_used_connections | 6      |   <- 历史最高同时连接数
| Questions            | 1723   |   <- 执行过的语句数
| Slow_queries         | 0      |   <- 慢查询次数
| Threads_connected    | 3      |   <- 当前连接数
| Threads_running      | 2      |   <- 正在执行 SQL 的连接数
| Uptime               | 371044 |   <- 已运行秒数
```

| 指标 | 关注点 |
|---|---|
| `max_connections` | 默认 151。报 `Too many connections` 时，先查是不是连接泄漏或连接池配太大，再考虑调高 |
| `wait_timeout` | 空闲连接多久被断开，默认 8 小时。连接池的空闲检测时间要比它短，否则会拿到已断开的连接 |
| `Threads_running` | 正在干活的连接数，突然升高通常说明有慢 SQL 或锁等待 |
| `Slow_queries` | 慢查询数量，配合慢查询日志（见 [04-performance.md](../practice/04-performance.md)）分析 |

### 8.4 其他常用查询

```sql
select * from information_schema.innodb_trx;   -- 当前所有事务，按 trx_started 找长事务
select * from sys.innodb_lock_waits;           -- 谁在等谁的锁
show engine innodb status;                     -- InnoDB 整体状态，包括最近一次死锁
select table_name, table_rows, round(data_length / 1024 / 1024, 2) data_mb, round(index_length / 1024 / 1024, 2) index_mb
from information_schema.tables where table_schema = 'itcast' order by data_length desc;   -- 各表大小
```

## 9. 小结

1. InnoDB 的读写都先在内存的 Buffer Pool 里进行，脏页由后台线程慢慢刷盘。
2. **redo log** 用「先写日志」保证 commit 之后宕机不丢数据；**undo log** 用来回滚和提供旧版本；**binlog** 用于主从复制和按时间点恢复。
3. redo log 和 binlog 用两阶段提交保证一致；「双 1 配置」保证数据不丢。
4. **MVCC** = 隐藏字段 + undo 版本链 + ReadView。RC 每次快照读生成 ReadView，RR 只在第一次生成，所以 RR 能做到可重复读。
5. 快照读可能读到旧数据，要基于最新值做修改，用当前读（`for update`）或条件更新。
6. 视图、存储过程、函数、触发器能看懂即可，业务逻辑尽量写在代码里。
7. 主从复制是异步的，写完马上读的场景要读主库。
8. 分库分表是最后的手段，要先选好分片键，并接受跨库 join、分布式事务、全局 ID 等问题。
9. 备份用 `mysqldump --single-transaction`，恢复靠「全量备份 + binlog」，并且要定期演练。
10. 排查线上问题先看 `show processlist`、`innodb_trx`、`innodb_lock_waits`。

---

上一章：[后端开发常见坑 🟢](10-backend-pitfalls.md) · [目录](../README.md)

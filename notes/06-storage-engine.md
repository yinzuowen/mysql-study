# 第 6 章 存储引擎 🟡

> **为什么要学**：建表时最后那句 `engine = InnoDB` 就是在选存储引擎。日常开发基本都用 InnoDB，但你需要知道：
> 一条 SQL 在 MySQL 内部经过了哪些环节、为什么 `rollback` 在有的表上不生效、为什么老项目里 `count(*)` 有时飞快有时很慢、数据最终存在磁盘的哪个文件里。
> 这些也是后面学[索引](07-index.md)、[锁](09-lock.md)、[MVCC 与日志](11-internals-and-ops.md)的基础。
>
> 本章的实验都在本机 MySQL（版本 26.10，Homebrew 安装）上实际跑过。实验用的 `tmp_ch06_*` 表做完已删除。

## 1. MySQL 体系结构

MySQL 从上到下分为四层：

```
                    客户端（Java 程序、mysql 命令行、Navicat ...）
                                     │
┌────────────────────────────────────▼────────────────────────────────────┐
│ 连接层   连接管理、身份认证、权限校验、连接池                              │
├─────────────────────────────────────────────────────────────────────────┤
│ 服务层   SQL 接口 → 解析器 → 优化器 → 执行器                               │
│          内置函数、视图、存储过程、触发器、binlog 都在这一层                │
├─────────────────────────────────────────────────────────────────────────┤
│ 引擎层   InnoDB │ MyISAM │ Memory │ ...   （插件式，可以按表选择）          │
├─────────────────────────────────────────────────────────────────────────┤
│ 存储层   磁盘上的数据文件、日志文件                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

| 层 | 做什么 | 和你相关的地方 |
|---|---|---|
| 连接层 | 建立连接、校验用户名密码和权限 | `max_connections`、连接池配置、`Too many connections` 报错 |
| 服务层 | 理解并执行 SQL：解析语法、选择索引、调用引擎 | 语法错误、`explain` 看到的执行计划都来自这一层 |
| 引擎层 | 真正读写数据，负责事务、锁、索引的实现 | 不同引擎能力差别很大 |
| 存储层 | 把数据持久化到文件系统 | `.ibd` 文件、redo log、binlog |

### 一条 select 是怎么执行的

以 `select * from t_user where name = '白起';` 为例：

1. **连接层**：客户端用账号密码连上 MySQL，校验通过后，这个连接后续的权限就确定了。
2. **解析器**：做词法分析（识别出 `select`、`t_user`、`name` 等）和语法分析，生成语法树。写错关键字会在这里报 `ERROR 1064`。
3. **预处理**：检查表和列是否存在、有没有权限。表名写错报 `ERROR 1146 Table doesn't exist`。
4. **优化器**：决定怎么执行最快，比如走 `idx_user_name` 索引还是全表扫描、多表连接的顺序。`explain` 看到的就是优化器的决定。
5. **执行器**：按执行计划调用存储引擎的接口，一行一行地取数据，过滤后返回给客户端。
6. **存储引擎**：先在内存（Buffer Pool）里找数据页，找不到再从磁盘读。

> MySQL 8.0 起已经**移除了查询缓存**，所以不用再纠结「查询缓存失效」的问题。

## 2. 存储引擎是什么

存储引擎就是**数据怎么存、怎么读、怎么加锁、支不支持事务**的具体实现。它是**按表**设置的，同一个库里不同的表可以用不同引擎。

```sql
-- 建表时指定
create table t_demo (id int primary key) engine = InnoDB;

-- 查看某张表用的引擎
show table status like 't_user';
select table_name, engine from information_schema.tables where table_schema = 'itcast';

-- 查看当前支持哪些引擎
show engines;
```

`show engines` 实测输出（节选）：

```
+--------------------+---------+------------------------------------------------------------+--------------+------+------------+
| Engine             | Support | Comment                                                    | Transactions | XA   | Savepoints |
+--------------------+---------+------------------------------------------------------------+--------------+------+------------+
| MyISAM             | YES     | MyISAM storage engine                                      | NO           | NO   | NO         |
| InnoDB             | DEFAULT | Supports transactions, row-level locking, and foreign keys | YES          | YES  | YES        |
| MEMORY             | YES     | Hash based, stored in memory, useful for temporary tables  | NO           | NO   | NO         |
| CSV                | YES     | CSV storage engine                                         | NO           | NO   | NO         |
| ARCHIVE            | YES     | Archive storage engine                                     | NO           | NO   | NO         |
+--------------------+---------+------------------------------------------------------------+--------------+------+------------+
```

- `Support = DEFAULT`：InnoDB 是默认引擎，建表不写 `engine` 就用它。
- `Transactions`：只有 InnoDB 支持事务。

## 3. InnoDB

InnoDB 从 MySQL 5.5 起是默认引擎，特点：

- **支持事务**（ACID），见[第 5 章](05-transaction.md)。
- **行级锁**，并发写的性能好，见[第 9 章](09-lock.md)。
- **支持外键**。
- **崩溃恢复**：靠 redo log，MySQL 意外宕机重启后数据不会丢，见[第 11 章](11-internals-and-ops.md)。
- 数据和索引存在一起，按主键组织（聚集索引），见[第 7 章](07-index.md)。

### 3.1 数据存在哪个文件

开启 `innodb_file_per_table`（默认开启）时，每张表一个 `.ibd` 文件，存这张表的数据和索引：

```sql
select @@datadir, @@innodb_file_per_table;
-- /opt/homebrew/var/mysql/   1
```

```
$ ls -l /opt/homebrew/var/mysql/itcast/
-rw-r-----  114688  t_dept.ibd
-rw-r-----  147456  t_emp.ibd
-rw-r-----  163840  t_user.ibd
...
```

数据目录下还有一些 InnoDB 公共文件：

| 文件 | 作用 |
|---|---|
| `ibdata1` | 系统表空间 |
| `undo_001`、`undo_002` | undo 日志表空间（回滚、MVCC） |
| `#innodb_redo/` | redo 日志（崩溃恢复） |
| `binlog.000001` ... | binlog（服务层的日志，不属于 InnoDB） |

> 表结构信息在 MySQL 8.0 之后存在数据字典里，不再有单独的 `.frm` 文件。

### 3.2 逻辑存储结构

```
表空间（Tablespace）    一张表对应一个 .ibd 文件
 └─ 段（Segment）        数据段（B+ 树叶子节点）、索引段（非叶子节点）、回滚段
     └─ 区（Extent）     固定 1MB，包含 64 个连续的页
         └─ 页（Page）    固定 16KB，磁盘和内存交换数据的最小单位
             └─ 行（Row） 真正的一条条记录
```

```sql
select @@innodb_page_size;   -- 16384，即 16KB
```

要点：

- **页是最小的读写单位**。哪怕只查一行，InnoDB 也会把这一行所在的整个 16KB 页读进内存。
- B+ 树的每个节点就是一个页，所以一棵 3 层的 B+ 树就能存上千万行数据（见第 7 章）。
- 每一行除了你定义的列，还有隐藏字段 `DB_TRX_ID`（最后修改它的事务 id）和 `DB_ROLL_PTR`（指向 undo log 里的旧版本），这是 MVCC 的基础（见第 11 章）。

### 3.3 Buffer Pool：InnoDB 的内存缓存

磁盘比内存慢几个数量级。InnoDB 在内存里开辟一块 **Buffer Pool**，缓存最近用过的数据页和索引页：

- **读**：先查 Buffer Pool，命中就直接返回；没命中再从磁盘读页，放进 Buffer Pool。
- **写**：先改 Buffer Pool 里的页（改完的页叫**脏页**），再由后台线程在合适的时机刷回磁盘。为了宕机不丢数据，写之前会先写 redo log（见第 11 章）。

```sql
select @@innodb_buffer_pool_size / 1024 / 1024 as buffer_pool_mb;   -- 128，默认 128MB

show global status where variable_name in (
  'Innodb_buffer_pool_pages_total', 'Innodb_buffer_pool_pages_free',
  'Innodb_buffer_pool_read_requests', 'Innodb_buffer_pool_reads');
```

本机实测：

```
| Innodb_buffer_pool_pages_total   | 8192  |   <- 8192 页 × 16KB = 128MB
| Innodb_buffer_pool_pages_free    | 6892  |   <- 还有空闲页
| Innodb_buffer_pool_read_requests | 53661 |   <- 逻辑读次数（向 Buffer Pool 要数据）
| Innodb_buffer_pool_reads         | 1042  |   <- 其中没命中、需要读磁盘的次数
```

**命中率** = 1 − reads / read_requests = 1 − 1042 / 53661 ≈ 98%。线上一般要求 99% 以上，太低说明 Buffer Pool 太小。生产环境的专用数据库服务器，通常把 `innodb_buffer_pool_size` 设为物理内存的 50%～75%。

## 4. MyISAM

MyISAM 是 MySQL 5.5 之前的默认引擎，现在新项目基本不用，但老项目和面试里还会遇到。

- **不支持事务**。
- **只有表锁**，写的时候锁整张表，并发写性能差。
- **不支持外键**。
- **不支持崩溃恢复**，宕机后可能要手动修复表。
- 数据和索引分开存放：`.MYD`（数据）、`.MYI`（索引）。
- 会单独保存表的总行数，所以不带 `where` 的 `count(*)` 直接返回，非常快。

### 实测：MyISAM 的 rollback 不生效

```sql
create table tmp_ch06_myisam (id int primary key, v int) engine = MyISAM;
create table tmp_ch06_innodb (id int primary key, v int) engine = InnoDB;

begin; insert into tmp_ch06_myisam values (1, 100); rollback;
begin; insert into tmp_ch06_innodb values (1, 100); rollback;

select 'MyISAM' engine, count(*) from tmp_ch06_myisam
union all
select 'InnoDB', count(*) from tmp_ch06_innodb;
```

```
+--------+---------------------+
| engine | rows_after_rollback |
+--------+---------------------+
| MyISAM |                   1 |   <- 回滚了，数据还在
| InnoDB |                   0 |   <- 回滚成功
+--------+---------------------+
```

对 MyISAM 表执行 `rollback` 时还有一条警告：

```
| Warning | 1196 | Some non-transactional changed tables couldn't be rolled back |
```

如果你的转账逻辑写在 MyISAM 表上，扣钱成功、加钱失败，钱就凭空消失了。

两种引擎在磁盘上的文件也不同（实测）：

```
tmp_ch06_innodb.ibd          <- InnoDB：数据 + 索引在一个文件
tmp_ch06_myisam.MYD          <- MyISAM：数据
tmp_ch06_myisam.MYI          <- MyISAM：索引
tmp_ch06_myisam_417.sdi      <- MyISAM：表结构信息
tmp_ch06_memory_419.sdi      <- Memory：只有表结构，数据在内存里
```

## 5. Memory

- 数据**存在内存里**，MySQL 重启后数据全部丢失，只剩表结构。
- 默认使用 **hash 索引**，等值查询很快，但不支持范围查询走索引。
- 只有表锁，不支持事务。
- 适合临时数据、缓存。实际项目里这类需求一般交给 Redis。

## 6. 三种引擎对比

| 特性 | InnoDB | MyISAM | Memory |
|---|---|---|---|
| 事务 | ✅ 支持 | ❌ | ❌ |
| 锁粒度 | 行锁 | 表锁 | 表锁 |
| 外键 | ✅ 支持 | ❌ | ❌ |
| 崩溃恢复 | ✅ 靠 redo log | ❌ 可能要修复表 | ❌ 数据全丢 |
| MVCC | ✅ | ❌ | ❌ |
| 索引结构 | B+ 树（聚集索引） | B+ 树（非聚集） | Hash（默认）/ B 树 |
| `count(*)` 不带 where | 需要扫描索引 | 直接返回保存的行数，极快 | 需要计算 |
| 磁盘文件 | `.ibd` | `.MYD` + `.MYI` | 只有表结构 |
| 数据位置 | 磁盘 + Buffer Pool 缓存 | 磁盘 + 操作系统缓存 | 内存 |

> 关于 `count(*)`：InnoDB 因为有 MVCC，不同事务看到的行数可能不同，所以没法保存一个固定的总行数，只能现数。优化器会挑一个最小的索引来扫描，比扫整张表快。

## 7. 怎么选择存储引擎

| 场景 | 选择 |
|---|---|
| 绝大多数业务表（订单、用户、库存……） | **InnoDB**，不用犹豫 |
| 只读、只追加的日志、报表 | 也用 InnoDB；数据量特别大时考虑归档到专门的系统（如 ClickHouse、ES） |
| 临时数据、缓存 | Redis，而不是 Memory 引擎 |
| 维护老项目遇到 MyISAM 表 | 有事务需求的，计划迁移：`alter table 表名 engine = InnoDB;`（大表要在低峰期做） |

## 8. 小结

1. MySQL 分为连接层、服务层、引擎层、存储层。SQL 解析、优化、执行在服务层，真正读写数据在引擎层。
2. 存储引擎按表设置，默认是 InnoDB，几乎所有业务表都应该用 InnoDB。
3. InnoDB 的数据存在 `.ibd` 文件里，结构是表空间 → 段 → 区（1MB）→ 页（16KB）→ 行。**页是读写的最小单位**。
4. Buffer Pool 是 InnoDB 的内存缓存，命中率最好在 99% 以上。
5. MyISAM 不支持事务、只有表锁、宕机可能丢数据，`rollback` 对它无效。
6. Memory 引擎数据在内存里，重启就丢，缓存需求用 Redis。

---

上一章：[事务 🟢](05-transaction.md) · [目录](../README.md) · 下一章：[索引 🟢 / 🟡](07-index.md)

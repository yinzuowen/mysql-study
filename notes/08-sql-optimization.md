# 第 8 章 SQL 优化 🟡

> 上线后最常收到的反馈是「这个页面好慢」「导出超时了」「数据库 CPU 报警」。这一章讲两件事：
> 1. **怎么找到慢的那条 SQL**，以及它为什么慢；
> 2. 插入、排序、分组、分页、计数、更新、连接这些**常见写法分别怎么优化**。
>
> 原则只有一条：**先定位，再优化，优化完用数据验证**。不要凭感觉改。
>
> 本章所有实验都在本机 MySQL（版本 26.10，InnoDB）上实际跑过，耗时会因机器不同而不同，看**相对差距**即可。主要用一张 100 万行的临时表（实验完已删除）：
>
> ```sql
> create table tmp_ch08_big (
>     id          bigint primary key auto_increment,
>     user_id     int            not null,   -- 1~20000
>     name        varchar(20)    not null,
>     age         tinyint unsigned not null, -- 18~57
>     city        varchar(20)    not null,   -- 5 个城市，每个 20 万行
>     status      tinyint        not null,
>     amount      decimal(10, 2) not null,
>     create_time datetime       not null,
>     remark      varchar(200)   not null
> ) engine = InnoDB default charset = utf8mb4;
> ```
>
> 造 100 万行测试数据可以用递归 CTE：
>
> ```sql
> set session cte_max_recursion_depth = 1000000;
> insert into tmp_ch08_big (user_id, name, age, city, status, amount, create_time, remark)
> with recursive seq(n) as (select 1 union all select n + 1 from seq where n < 1000000)
> select n % 20000 + 1, concat('user', n), 18 + n % 40,
>        elt(1 + n % 5, '北京', '上海', '广州', '深圳', '杭州'), n % 4,
>        (n % 1000) + 0.99, '2024-01-01' + interval n minute, repeat('x', 100)
> from seq;
> ```

## 1. 先定位：找到慢 SQL

### 1.1 看数据库主要在干什么

```sql
show global status like 'Com_______';   -- Com_select、Com_insert、Com_update、Com_delete 的执行次数
```

以查询为主的库，优化重点在索引和查询；以写入为主的库，重点在插入、更新和索引数量。

### 1.2 慢查询日志

慢查询日志会记录执行时间超过 `long_query_time` 秒的 SQL。

```sql
select @@slow_query_log, @@long_query_time, @@slow_query_log_file;
```
```
| @@slow_query_log | @@long_query_time | @@slow_query_log_file                                  |
| 1                | 10.000000         | /opt/homebrew/var/mysql/Zuowen-YinMacBook-Pro-slow.log |
```

本机已经开了，但阈值是默认的 10 秒，太宽松。线上一般设 1 秒或更低：

```sql
set global long_query_time = 1;   -- 对新连接生效；写进 my.cnf 才能重启后保留
set long_query_time = 0.5;        -- 只对当前会话生效，适合临时测试
```

实测：当前会话设成 0.5 秒，执行一条 0.6 秒的查询，日志里多了这样一条：

```
# Time: 2026-11-20T12:45:32.749891Z
# User@Host: root[root] @ localhost [127.0.0.1]  Id:   375
# Query_time: 0.675045  Lock_time: 0.000012 Rows_sent: 1  Rows_examined: 24
SET timestamp=1795178732;
select sleep(0.6), count(*) from t_user;
```

重点看 **`Query_time`（耗时）和 `Rows_examined`（扫描行数）**。返回 1 行却扫描了几十万行，基本就是没走索引。日志多了以后，用 MySQL 自带的 `mysqldumpslow` 汇总：

```bash
mysqldumpslow -s t -t 10 /opt/homebrew/var/mysql/Zuowen-YinMacBook-Pro-slow.log   # 按总耗时排前 10
```

### 1.3 show profiles：看时间花在哪个阶段

```sql
set profiling = 1;
select count(*) from tmp_ch08_big where age = 30;      -- age 没有索引
select * from tmp_ch08_big where id = 10;
select count(*) from tmp_ch08_big where city = '北京';  -- city 有索引
show profiles;
```
```
| Query_ID | Duration   | Query                                               |
| 1        | 0.21187300 | select count(*) from tmp_ch08_big where age = 30    |
| 2        | 0.00014200 | select * from tmp_ch08_big where id = 10            |
| 3        | 0.03135400 | select count(*) from tmp_ch08_big where city='北京' |
```

```sql
show profile for query 1;
```
```
| Opening tables   | 0.000140 |
| optimizing       | 0.000025 |
| statistics       | 0.000041 |
| preparing        | 0.000045 |
| executing        | 0.211091 |   <- 几乎全部时间花在执行上（全表扫描）
| ...              |          |
```

`show profiles` 在新版本里已标记为过时，但学习时很直观。

### 1.4 explain 和 explain analyze

`explain` 看**计划**（估算），`explain analyze` 会**真正执行一遍**，给出每一步的实际耗时和行数：

```sql
explain analyze select * from tmp_ch08_big order by id limit 900000, 10;
```
```
-> Limit/Offset: 10/900000 row(s)  (cost=86269 rows=10) (actual time=286..286 rows=10 loops=1)
    -> Index scan on tmp_ch08_big using PRIMARY  (cost=86269 rows=900010) (actual time=0.0799..268 rows=900010 loops=1)
```

一眼看出：为了返回 10 行，读了 90 万行。`actual time=0.0799..268` 是这一步拿到第一行和最后一行的时间（毫秒），`loops` 是执行了几次。

> ⚠️ `explain analyze` 会真正执行语句，不要对 `update`、`delete` 用。

`explain` 各字段的含义见[第 7 章](07-index.md#6-explain-详解)。

## 2. insert 优化

### 2.1 三种写法对比

往表里插入 1 万行（每行 4 个字段）：

| 写法 | 耗时 |
|---|---|
| 1 万条 `insert`，每条自动提交 | **2.66 秒** |
| 1 万条 `insert`，放在一个事务里，最后 `commit` | 0.56 秒 |
| 每条 `insert` 带 1000 行 `values`，共 10 条 | **0.14 秒** |

```sql
-- ❌ 一条一条插，每条都是一次网络往返 + 一次事务提交（要刷盘）
insert into t_user (name, age) values ('a', 18);
insert into t_user (name, age) values ('b', 19);

-- ✅ 手动控制事务，只在最后提交一次
begin;
insert into t_user (name, age) values ('a', 18);
insert into t_user (name, age) values ('b', 19);
commit;

-- ✅✅ 批量插入，一条语句插多行
insert into t_user (name, age) values ('a', 18), ('b', 19), ('c', 20);
```

后端代码里：MyBatis 用 `<foreach>` 拼批量 `values`，或者用 `ExecutorType.BATCH`；JDBC 用 `addBatch()`，MySQL 连接串加 `rewriteBatchedStatements=true` 才会真正合并成批量语句。**每批 500–1000 行**比较合适，太大会超过 `max_allowed_packet`，事务也太大。

### 2.2 大量数据：load data

导入几十万、上百万行的 CSV，用 `load data` 比 `insert` 快得多：

```bash
mysql --local-infile=1 -uroot -p
```
```sql
set global local_infile = 1;   -- 服务端也要开启，本机默认是 0
load data local infile '/path/to/user.csv' into table t_user
fields terminated by ',' lines terminated by '\n';
```

### 2.3 主键顺序插入与页分裂

InnoDB 的数据按主键顺序存放在一页一页的 B+ 树叶子节点里（见[第 7 章](07-index.md)）：

```
主键顺序插入（自增 id）：只往最后一页追加，写满了就开新页

  [1 2 3 4] → [5 6 7 8] → [9 10 _ _]   ← 新数据总是写在这里

主键乱序插入（如 UUID）：新数据可能要插进中间一个已经写满的页

  [10 20 30 40] → [50 60 70 80]
         ↑ 要插入 25
  页满了 → 页分裂：新开一页，把原来一半的数据挪过去，再调整链表指针

  [10 20 25 _] → [30 40 _ _] → [50 60 70 80]   ← 两个半空的页
```

页分裂要挪数据，还会留下很多半空的页，浪费空间。实测：先插 30 万行，再插 10 万行：

| | 自增 `bigint` 主键 | 随机字符串主键 `char(36)` |
|---|---|---|
| 插入 30 万行 | 1.60 秒 | 2.48 秒 |
| 再插入 10 万行 | 0.43 秒 | 0.85 秒 |
| 主键索引叶子页数 | 3670 | 6264 |
| 数据大小 | 57.6 MB | 114.0 MB |

随机主键的表大了将近一倍（一部分是因为 `char(36)` 本身比 `bigint` 长，大部分是页分裂留下的空间），插入也更慢。

> 注意：MySQL 的 `uuid()` 是基于时间的，同一台机器连续生成的值大致递增，实测和自增差别不大。但应用里常用的 `UUID.randomUUID()` 是完全随机的，就是上面这种情况。

删除数据时，如果一页里删掉的数据超过一半（`MERGE_THRESHOLD`，默认 50%），InnoDB 会尝试和相邻页**合并**。

## 3. 主键设计

1. **一定要有主键**，否则 InnoDB 会用隐藏的 row_id。
2. **尽量短**：二级索引的叶子节点都存了主键值，主键越长，所有二级索引都越大。
3. **尽量顺序插入**：用 `auto_increment` 自增，或者雪花算法这类趋势递增的 ID。
4. **不要用 UUID、身份证号、手机号这类无序或业务字段做主键**。业务字段可能会变，也可能需要脱敏，加唯一索引就够了。
5. 业务主键用 `bigint`，不要用 `int`（最大约 21 亿）。

分库分表后自增 ID 会重复，一般用**雪花算法**（64 位、趋势递增）生成全局唯一 ID，见[第 11 章](11-internals-and-ops.md)。

## 4. order by 优化

### 4.1 两种排序方式

| Extra | 含义 | 性能 |
|---|---|---|
| `Using index` | 直接按索引顺序读出来，数据本来就是有序的，**不用排序** | 快 |
| `Using filesort` | 先把数据读出来，再在排序缓冲区（`sort_buffer_size`，本机 256KB）里排序，放不下还要用磁盘临时文件 | 慢 |

### 4.2 实测

索引 `idx_city_ct(city, create_time)`：

| 查询 | Extra |
|---|---|
| `select id, city, create_time ... order by city, create_time` | `Using index` |
| `... order by city desc, create_time desc` | `Backward index scan; Using index`（反向读索引，也不用排序） |
| `... order by create_time, city` | `Using index; Using filesort`：顺序和索引不一致 |
| `... order by city asc, create_time desc` | `Using index; Using filesort`：一升一降 |
| `select * ... where city = '北京' order by create_time desc` | `Backward index scan`：等值条件 + 排序，可以用索引 |
| `select * ... where city = '北京' order by amount` | `Using filesort`：amount 不在索引里 |
| `select * ... order by age` | `type=ALL; Using filesort`：age 没有索引 |

一升一降的情况，MySQL 8 可以建**降序索引**解决：

```sql
create index idx_city_ct_desc on tmp_ch08_big(city asc, create_time desc);
-- 之后 order by city asc, create_time desc limit 10 变成 Using index
```

耗时对比（`limit 10`）：

| 查询 | 耗时 |
|---|---|
| `order by city asc, create_time asc limit 10`（按索引顺序） | 0.000 秒 |
| `order by city asc, create_time desc limit 10`（filesort） | **约 0.21 秒** |

用索引排序时，读到 10 行就可以停；filesort 必须把 100 万行都读出来排完，才知道前 10 行是谁。

### 4.3 优化方法

1. 给排序字段建索引，**多字段排序时遵循最左前缀**，并且和 `where` 的等值条件一起考虑：`where a = ? order by b` 建 `(a, b)`。
2. 尽量用覆盖索引。
3. 多字段排序一升一降时，建索引时指定方向（`asc` / `desc`）。
4. 不可避免要 filesort 时，可以适当调大 `sort_buffer_size`（会话级），避免用到磁盘。

## 5. group by 优化

分组需要把相同的值放在一起。如果数据已经按分组字段有序（有索引），就可以直接分组；否则要建**临时表**（`Using temporary`）。

| 查询 | type | Extra | 耗时 |
|---|---|---|---|
| `select age, count(*) ... group by age`（age 无索引） | ALL | `Using temporary` | 约 0.25–0.31 秒 |
| 给 age 建索引后，同一条查询 | index | `Using index` | 约 0.12 秒 |
| `select city, count(*) ... group by city` | index | `Using index` | 约 0.15 秒 |
| `select create_time, count(*) ... where city = '北京' group by create_time` | ref | `Using index`：where 用第 1 列、group by 用第 2 列，满足最左前缀 | — |
| `select city, age, count(*) ... group by age, city` | ALL | `Using temporary`：顺序和索引不一致 | — |

优化方法和 order by 一样：**给分组字段建索引，多字段分组遵循最左前缀**。

## 6. limit 深分页

### 6.1 问题

`limit 900000, 10` 的意思是「跳过前 90 万行，取 10 行」。MySQL 没法直接跳到第 90 万行，只能**读出 90 万零 10 行，再扔掉前 90 万行**：

| 查询 | 耗时 |
|---|---|
| `select * from tmp_ch08_big order by id limit 0, 10` | 0.001 秒 |
| `... order by id limit 500000, 10` | 约 0.15 秒 |
| `... order by id limit 900000, 10` | 约 0.25 秒 |

翻得越往后越慢。业务里更常见的是带条件的分页，比如「北京的订单按时间排序」，索引 `idx_city_ct(city, create_time)`：

```sql
select * from tmp_ch08_big where city = '北京' order by create_time limit 150000, 10;
```

这条要沿着二级索引读 15 万条，**每条都回表取整行**，然后扔掉。

### 6.2 方法一：延迟关联（先查 id，再回表）

```sql
select b.*
from tmp_ch08_big b
join (select id from tmp_ch08_big where city = '北京' order by create_time limit 150000, 10) t
  on b.id = t.id;
```

子查询只查 `id`，在二级索引上就能完成（覆盖索引，`Using index`），不用回表；最后只对 10 个 id 回表。

### 6.3 方法二：游标分页（记住上一页的位置）

前端把上一页最后一条的排序值传回来，下一页从它后面开始查：

```sql
-- 上一页最后一条：create_time = '2025-06-04 20:00:00', id = 750000
select * from tmp_ch08_big
where city = '北京' and create_time > '2025-06-04 20:00:00'
order by create_time
limit 10;
```

排序字段可能重复时，加上 id 兜底，保证不重不漏：

```sql
where city = '北京'
  and (create_time > '2025-06-04 20:00:00'
       or (create_time = '2025-06-04 20:00:00' and id > 750000))
order by create_time, id
limit 10;
```

### 6.4 对比

| 写法 | 耗时 |
|---|---|
| `limit 150000, 10` | 约 0.18–0.20 秒 |
| 延迟关联 | 约 0.03–0.05 秒 |
| 游标分页（`create_time > ?`） | **约 0.001 秒**，`type=range`，翻到哪一页都一样快 |
| 主键游标 `where id > 900000 order by id limit 10` | 0.000 秒（对比 `limit 900000, 10` 的 0.25 秒） |

实测延迟关联和游标分页返回的数据和原始写法一致。

怎么选：

- **游标分页**最快，适合「加载更多」「下一页」这种只能一页页往后翻的场景（App 信息流、后台导出）。缺点是不能直接跳到第 N 页。
- **延迟关联**能跳页，适合后台管理系统的分页表格。
- 产品上限制最大页数（比如最多翻 100 页），很多搜索引擎都这么做。

## 7. count 优化

### 7.1 几种写法的区别

| 写法 | 统计什么 |
|---|---|
| `count(*)` | 行数，**推荐** |
| `count(1)` | 行数，和 `count(*)` 一样 |
| `count(主键)` | 行数（主键不会是 null） |
| `count(字段)` | 该字段**不为 null** 的行数，字段可空时结果可能不同 |

`count(*)` 是 SQL 标准写法，MySQL 专门做了优化：不取任何字段值，并且会**挑最小的索引**来扫。实测 100 万行的表，`count(*)`、`count(1)`、`count(id)`、`count(city)` 的执行计划都是扫描二级索引 `idx_city_ct`（比主键索引小）：

| 写法 | 执行计划 | 耗时 |
|---|---|---|
| `count(*)` | index，`idx_city_ct`，Using index | 约 0.08 秒 |
| `count(1)` | 同上 | 约 0.08–0.10 秒 |
| `count(id)` | 同上 | 约 0.09 秒 |
| `count(city)` | 同上 | 约 0.10 秒 |
| `count(remark)`（remark 没有索引） | ALL | 约 0.05–0.08 秒 |

在本机上几种写法差距很小，都在误差范围内（`count(remark)` 扫主键索引也不慢，因为数据全在内存里）。**结论：统计行数就用 `count(*)`，不用纠结 `count(1)`。**

### 7.2 为什么 InnoDB 的 count(*) 慢

MyISAM 把总行数存在表信息里，`count(*)` 直接返回。InnoDB 因为有事务（MVCC），不同事务看到的行数可能不一样，只能**一行行数**。100 万行要 0.08 秒，1 亿行就要好几秒。

### 7.3 优化思路

- `information_schema.tables` 的 `table_rows` 是**估算值**（本机 100 万行显示 989334），可以用于「大约有多少数据」这种场景，不能用于精确计数。
- 需要实时精确计数时，**自己维护计数**：用 Redis 计数，或者建一张计数表，在同一个事务里更新。
- 分页接口的总数：数据量大时考虑不显示精确总页数，或者只在第一页查一次总数后缓存起来。

## 8. update 优化

**`update`、`delete` 的 `where` 条件一定要走索引**，否则行锁会锁住整张表。实测在 2 万行的表上：

```sql
begin;
update tmp_ch08_u set level = level where nick = 'nick5';
select count(*) from performance_schema.data_locks where object_name = 'tmp_ch08_u' and lock_type = 'RECORD';
```

| | 锁住的记录数 |
|---|---|
| nick 没有索引 | **20044**（全部行 + 间隙） |
| 给 nick 建索引后 | 3 |

只想改 1 行，却锁住了 2 万行，期间其他事务改这张表的任何数据都要等。原理见[第 9 章 锁](09-lock.md)。

另外：

- 批量更新、删除大量数据时**分批执行**，比如每次 `limit 1000`，避免一个大事务长时间占着锁、产生大量 undo log。
- 不要在事务里调用远程接口、做耗时计算。

## 9. join 优化

### 9.1 连接字段要有索引

用户表 `tmp_ch08_u`（2 万行），订单表 `tmp_ch08_big`（100 万行），查前 50 个用户里 level = 0 的用户的订单：

```sql
select u.nick, b.id, b.amount
from tmp_ch08_u u
join tmp_ch08_big b on b.user_id = u.id
where u.level = 0 and u.id <= 50;
```

| | 执行计划 | 耗时 |
|---|---|---|
| `b.user_id` 没有索引 | 先全表扫描 b（100 万行），每行再去 u 按主键查 | 约 0.20 秒 |
| 给 `b.user_id` 建索引后 | 先查 u（50 行），每行再去 b 按 `idx_user_id` 查 | **约 0.002 秒** |

```
-- 没有索引时 explain analyze 的关键行
-> Table scan on b  (actual time=0.159..223 rows=1e+6 loops=1)

-- 有索引时 explain
| u | range | PRIMARY     | rows=50 |
| b | ref   | idx_user_id | rows=49 |
```

**被驱动表（后访问的表）的连接字段必须有索引**，这是 join 优化最重要的一条。

如果连接字段两边都没有索引，MySQL 8 会用 **hash join**：把小表读进内存建哈希表，再全表扫描大表去匹配。比老版本的嵌套循环好很多，但大表仍然要全表扫描（实测按 `b.name = u.nick` 连接，扫描了 100 万行，耗时约 0.35 秒）。

### 9.2 小表驱动大表

嵌套循环连接是：**外层（驱动表）每一行，都去内层（被驱动表）查一次**。

- 驱动表 50 行 × 被驱动表按索引查 1 次 = 50 次索引查找 ✅
- 驱动表 100 万行 × 被驱动表按索引查 1 次 = 100 万次索引查找 ❌

所以要让**过滤后结果少的表做驱动表**。上面的例子里，MySQL 自动选了 u 做驱动表。优化器一般能选对，你要做的是：**给被驱动表的连接字段建索引，并且尽量在驱动表上加过滤条件**。

### 9.3 其他

- `left join` 的左表一定是驱动表，所以要把数据少的表放左边（业务允许的话）。
- 连接字段的**类型和字符集要一致**，否则会发生隐式转换，索引失效。
- 阿里巴巴 Java 开发手册的建议：**超过三张表禁止 join**。复杂查询拆成几次单表查询，在代码里组装。

## 10. 子查询改 join

老版本（MySQL 5.5 及以前）的 `in (子查询)` 经常被执行成「外表每一行都执行一次子查询」，非常慢，所以有了「子查询改 join」的说法。

MySQL 8 已经会自动把 `in (子查询)` 转成连接（半连接，semijoin）。实测下面两条的执行计划完全一样，耗时都在 0.002 秒左右：

```sql
select * from tmp_ch08_big where user_id in (select id from tmp_ch08_u where level = 0 and id <= 100);

select b.* from tmp_ch08_big b join tmp_ch08_u u on b.user_id = u.id where u.level = 0 and u.id <= 100;
```

要注意的是 `select` 列表里的**相关子查询**，`explain` 显示为 `DEPENDENT SUBQUERY`，外层每一行都执行一次：

```sql
-- 相关子查询：DEPENDENT SUBQUERY，外层 2000 行就执行 2000 次子查询
select u.id, (select count(*) from tmp_ch08_big b where b.user_id = u.id) cnt
from tmp_ch08_u u where u.id <= 2000;

-- 改成 join + group by
select u.id, count(b.id) cnt
from tmp_ch08_u u left join tmp_ch08_big b on b.user_id = u.id
where u.id <= 2000 group by u.id;
```

实测因为 `b.user_id` 有索引，两种写法都在 0.02 秒左右。**相关子查询本身不一定慢，慢的是子查询里没有索引**，这时外层有多少行就要全表扫描多少次。看到 `DEPENDENT SUBQUERY` 时，检查子查询的条件有没有走索引。

## 11. 避免 select *

1. **用不上覆盖索引**，每行都要回表（见[第 7 章](07-index.md#41-覆盖索引不用回表)）。
2. **多传数据**：`remark`、`content` 这类大字段，接口用不到也会被读出来、通过网络传给应用，再转成对象。
3. **表结构变化时容易出问题**：加了新字段，`select *` 的结果跟着变；字段名重复的多表查询还会互相覆盖。

只查接口需要的列。MyBatis 里给每个查询写明确的列清单。

## 12. 数据量更大时

单条 SQL 优化到头之后，还慢就要从架构上解决，入门阶段了解思路即可：

| 手段 | 解决什么 | 说明 |
|---|---|---|
| 缓存（Redis） | 读多写少的热点数据 | 商品详情、配置、排行榜，先查缓存，没有再查库 |
| 读写分离 | 读请求太多 | 主库写，从库读，见[第 11 章](11-internals-and-ops.md) |
| 分库分表 | 单表数据太多（通常千万级以上）、单库扛不住写入 | 按用户 ID、时间等拆分，见[第 11 章](11-internals-and-ops.md) |
| 冷热分离、归档 | 历史数据多、但很少访问 | 把一年前的订单挪到历史表 |
| 搜索引擎 | 模糊搜索、多条件组合筛选 | Elasticsearch |

## 13. 小结

1. **先定位再优化**：慢查询日志找到 SQL → `explain` / `explain analyze` 看原因 → 改完用数据对比。
2. **insert**：批量 `values`、手动提交事务；大量数据用 `load data`；主键要顺序递增，避免页分裂。
3. **主键**：自增或趋势递增的 `bigint`，不用 UUID 和业务字段。
4. **order by / group by**：给排序、分组字段建索引，遵循最左前缀，避免 `Using filesort` 和 `Using temporary`。
5. **深分页**：游标分页最快；需要跳页用延迟关联；产品上限制最大页数。
6. **count**：用 `count(*)`；InnoDB 只能逐行数，大表精确计数要自己维护。
7. **update / delete**：`where` 必须走索引，否则锁全表；大批量分批执行。
8. **join**：被驱动表的连接字段要有索引；小表驱动大表；不超过三张表。
9. **子查询**：MySQL 8 会自动优化 `in` 子查询，关注 `DEPENDENT SUBQUERY` 里有没有索引。
10. 只查需要的列，不写 `select *`。

---

上一章：[索引 🟢 / 🟡](07-index.md) · [目录](../README.md) · 下一章：[锁 🟡](09-lock.md)

# 第 7 章 索引 🟢 / 🟡

> 写业务时最常遇到的性能问题就是「这条查询怎么这么慢」，而十有八九是**没建索引、或者建了没用上**。
> 学完这一章你应该能做到：看懂 `explain`，知道一条 SQL 有没有走索引、为什么没走；给新表设计合理的索引；在代码评审里指出「这个 `where` 会让索引失效」。
>
> 本章所有实验都在本机 MySQL（版本 26.10，InnoDB，页大小 16KB）上实际跑过，耗时会因机器不同而不同。用到两张临时表（实验完已删除）：
> - `tmp_ch07_user`：复制自 [t_user](../data/t_user.sql)，24 行，索引有 `PRIMARY(id)`、`idx_user_name(name)`、`idx_user_phone(phone)` 唯一、`idx_profession_age_status(profession, age, status)`。
> - `tmp_ch07_big`：50 万行，字段 `id, name, phone, age, city, create_time`，city 只有 5 种值。
>
> `explain` 的更多例子见 [04-performance.sql](../practice/04-performance.sql)。本机 `explain` 默认输出树形格式，本章都用 `explain format=traditional` 看表格。

## 1. 没有索引为什么慢

没有索引时，MySQL 只能**从第一行开始一行一行地比较**，叫全表扫描。在 50 万行的表里按手机号查一个人：

```sql
select id, name from tmp_ch07_big where phone = '13800400000';
```

| | 耗时 | explain 的 type | 扫描行数 |
|---|---|---|---|
| 没有索引 | 约 0.10 秒 | `ALL` | 约 50 万 |
| 给 phone 建索引后 | 约 0.000–0.001 秒 | `ref` | 1 |

`explain analyze` 能看到真实执行情况：

```
-- 没有索引
-> Filter: (tmp_ch07_big.phone = '13800400000')  (actual time=113..154 rows=1 loops=1)
    -> Table scan on tmp_ch07_big  (actual time=0.266..108 rows=500000 loops=1)

-- 有索引
-> Index lookup on tmp_ch07_big using idx_phone (phone = '13800400000')  (actual time=0.0486..0.0505 rows=1 loops=1)
```

为了找 1 行，全表扫描读了 50 万行。数据量越大差距越大：0.1 秒看起来不多，但接口每秒被调用 100 次，数据库 CPU 就满了。

**索引就是一种排好序的数据结构**，像书的目录，让 MySQL 不用翻整本书就能直接定位。

## 2. 索引为什么用 B+ 树

数据在磁盘上，读磁盘比读内存慢得多。InnoDB 以**页（默认 16KB）**为单位读写磁盘，所以索引结构的目标是：**查一条数据要读的页越少越好**，也就是树越矮越好。

### 2.1 几种候选结构

| 结构 | 问题 |
|---|---|
| 二叉搜索树 | 主键按顺序插入时会退化成一条链表，查找变成 O(n) |
| 红黑树（平衡二叉树） | 不会退化，但每个节点只有 2 个子节点，100 万行树高约 20，可能要读 20 次磁盘 |
| 哈希表 | 等值查询 O(1)，但**不支持范围查询和排序**（`>`、`between`、`order by` 都用不上） |
| B 树 | 每个节点存多个键，树很矮；但非叶子节点也存数据，一页能放的键变少，范围查询要在树里来回跳 |
| **B+ 树** | 非叶子节点只存键和指针，一页能放上千个键，树很矮；数据全在叶子节点，叶子节点用链表串起来，范围查询顺着链表往后读就行 |

```
二叉搜索树按顺序插入 1,2,3,4,5 会退化成链表：

  1
   \
    2
     \
      3
       \
        4
         \
          5
```

### 2.2 B+ 树长什么样

以主键索引为例（每个节点就是一页）：

```
                         ┌──────────────────────┐
  根节点（非叶子）         │   10   │   20         │      只存主键 + 指向下层的指针
                         └───┬────────┬────────┬─┘
              ┌──────────────┘        │        └──────────────┐
              ▼                       ▼                       ▼
  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐
  │ 1 │ 3 │ 7 │ ...     │⇄│ 10 │ 12 │ 15 │ ... │⇄│ 20 │ 22 │ 24 │ ... │   叶子节点：存整行数据
  │ 整行 │ 整行 │ 整行   │  │ 整行 │ 整行 │ 整行  │  │ 整行 │ 整行 │ 整行  │   相邻叶子之间是双向链表
  └────────────────────┘  └────────────────────┘  └────────────────────┘
```

- 查 `id = 12`：根节点 → 判断在 10–20 之间 → 第二个叶子 → 找到。读 2 页。
- 查 `id between 12 and 22`：先找到 12，再顺着叶子链表往右读，读到 22 为止。

### 2.3 三层 B+ 树能存多少行

假设主键是 `bigint`（8 字节），指针 6 字节，一行数据约 1KB：

- 非叶子节点一页能放：16384 ÷ (8 + 6) ≈ **1170** 个指针
- 叶子节点一页能放：16KB ÷ 1KB = **16** 行
- 两层：1170 × 16 ≈ 1.9 万行
- 三层：1170 × 1170 × 16 ≈ **2190 万行**

也就是说，**两千万行的表，按主键查一行只需要读 3 页**。而且根节点和上层节点通常常驻内存，实际读磁盘可能只有 1 次。

实测：`tmp_ch07_big` 50 万行，每行很小（约 70 字节），主键索引只有 2051 个叶子页、约 33MB。

## 3. 索引分类

### 3.1 按功能

| 类型 | 关键字 | 说明 | 一张表可以有几个 |
|---|---|---|---|
| 主键索引 | `primary key` | 唯一、非空，InnoDB 用它组织整张表 | 1 个 |
| 唯一索引 | `unique` | 值不能重复（可以有多个 `null`） | 多个 |
| 普通索引 | `index` / `key` | 只为加速查询 | 多个 |
| 联合索引 | `index(a, b, c)` | 一个索引包含多列，**最常用** | 多个 |
| 前缀索引 | `index(col(n))` | 只取字符串的前 n 个字符建索引 | 多个 |
| 全文索引 | `fulltext` | 按词搜索长文本 | 多个 |

### 3.2 按存储方式：聚集索引和二级索引 🟡

这是理解后面所有内容的关键。

| | 聚集索引 | 二级索引（辅助索引） |
|---|---|---|
| 是谁 | 主键索引 | 除主键外的其他索引 |
| 叶子节点存什么 | **整行数据** | **索引列的值 + 主键值** |
| 一张表有几个 | 只有 1 个 | 可以有多个 |

没有主键时，InnoDB 会用第一个非空唯一索引当聚集索引；连这个也没有，就自动生成一个隐藏的 6 字节 `row_id`。所以**建表一定要显式定义主键**。

### 3.3 回表

```sql
select * from t_user where name = '白起';
```

`name` 上有二级索引 `idx_user_name`，执行过程：

```
① 在二级索引 idx_user_name 里找 '白起'          ② 拿着主键 10 去聚集索引里找整行
                                              
  ┌───────────────────────┐                    ┌──────────────────────┐
  │ 安琪拉 │ 白起 │ 曹操 │ … │                    │      10   │   20      │
  └────────┬──────────────┘                    └──────┬─────────────────┘
           ▼                                          ▼
  叶子：('白起', 10)  ────── 主键 id=10 ──────▶   叶子：(10, 白起, 17799990009, ...整行)
```

先查二级索引拿到主键，再回到聚集索引取整行，这个过程叫**回表**。回表多一次查找；如果匹配的行很多，就会有大量随机读，这是后面「优化器放弃索引」的原因。

## 4. 覆盖索引与索引下推

### 4.1 覆盖索引：不用回表

如果要查的列**全都在二级索引里**，就不用回表了。二级索引的叶子节点本来就有主键值，所以主键也算在内。

```sql
explain format=traditional select id, name from tmp_ch07_user where name = '白起';
-- type=ref, key=idx_user_name, Extra=Using index        ← 覆盖索引，不回表

explain format=traditional select * from tmp_ch07_user where name = '白起';
-- type=ref, key=idx_user_name, Extra=NULL               ← 要取其他列，需要回表
```

`Extra` 里出现 **`Using index`** 就表示用到了覆盖索引。这是「不要写 `select *`」最实际的理由之一。

覆盖索引在数据量大时效果明显。在 50 万行的 `tmp_ch07_big` 上，`city` 有索引 `idx_city_age(city, age)`：

| 查询 | 走索引 | 不走索引（`ignore index`） |
|---|---|---|
| `select sum(age) ... where city = '北京'`（age 在索引里，覆盖） | **约 0.03 秒** | 约 0.08 秒 |
| `select sum(length(name)) ... where city = '北京'`（name 不在索引里，要回表 10 万次） | 约 0.10 秒 | **约 0.08 秒** |

同样走索引，覆盖索引比全表扫描快一倍多；要回表 10 万次时，反而比全表扫描还慢。

### 4.2 索引下推（ICP）🟡

联合索引 `(profession, age, status)`，查询：

```sql
select * from tmp_ch07_user where profession = '软件工程' and status = '0';
-- type=ref, key_len=83（只用到 profession）, Extra=Using index condition
```

`status` 因为跳过了 `age`，不能用来**定位**。但 `status` 的值就在索引里：

- 没有索引下推：按 `profession` 找到 4 条，**4 条都回表**取整行，再判断 `status`。
- 有索引下推（MySQL 5.6+，默认开启）：在二级索引里**先判断 `status`**，不符合的直接跳过，只对符合的回表。

`Extra` 里的 **`Using index condition`** 就表示用了索引下推，减少了回表次数。

## 5. 创建、查看、删除索引

```sql
-- 建表时创建
create table t_demo (
    id    bigint primary key auto_increment,
    phone char(11) not null,
    name  varchar(20),
    email varchar(100),
    unique key uk_phone (phone),
    key idx_name (name)
);

-- 给已有表加索引
create index idx_name on t_user(name);                                    -- 普通索引
create unique index uk_phone on t_user(phone);                            -- 唯一索引
create index idx_profession_age_status on t_user(profession, age, status); -- 联合索引
create index idx_email_5 on t_user(email(5));                             -- 前缀索引
alter table t_user add index idx_name(name);                              -- 另一种写法

-- 查看
show index from t_user;

-- 删除
drop index idx_name on t_user;
alter table t_user drop index idx_name;
```

命名习惯：普通索引 `idx_列名`，唯一索引 `uk_列名`。

### 前缀索引

字符串很长时，可以只对前几个字符建索引。前缀长度看**选择性**（不重复的值 ÷ 总行数，越接近 1 越好）：

```sql
select count(distinct email) / count(*)          full_sel,
       count(distinct left(email, 3)) / count(*) p3,
       count(distinct left(email, 5)) / count(*) p5,
       count(distinct left(email, 8)) / count(*) p8
from tmp_ch07_user;
```
```
| full_sel | p3     | p5     | p8     |
| 1.0000   | 0.9167 | 0.9583 | 0.9583 |
```

取前 5 个字符选择性已经和取 8 个一样，所以选 5。注意：**前缀索引用不了覆盖索引**，因为索引里只有前 5 个字符，MySQL 必须回表确认完整的值。实测 `select id, email ... where email = '...'` 的 `Extra` 仍然是 `Using where`，不是 `Using index`。

### 全文索引

`like '%工程%'` 用不上普通索引，全文索引可以按词搜索。中文要指定 `ngram` 分词器：

```sql
create fulltext index ft_profession on tmp_ch07_user(profession) with parser ngram;
select id, name, profession from tmp_ch07_user where match(profession) against('工程');
-- explain: type=fulltext
```

全文索引功能有限，业务里做搜索一般用 Elasticsearch，了解即可。

## 6. explain 详解

```sql
explain format=traditional select ...;
```

| 字段 | 含义 |
|---|---|
| id | 查询序号。id 相同从上往下执行；id 不同，大的先执行 |
| select_type | `SIMPLE` 简单查询、`PRIMARY` 外层查询、`SUBQUERY` 子查询、`DERIVED` 派生表、`UNION` |
| table | 访问的表 |
| **type** | 访问类型，**最重要** |
| possible_keys | 可能用到的索引 |
| **key** | 实际用到的索引，`NULL` 表示没用索引 |
| **key_len** | 用到的索引长度（字节），用来判断联合索引用到了几列 |
| ref | 和索引比较的是什么：`const` 常量，或者另一张表的列 |
| **rows** | 预计要扫描的行数（估算值） |
| filtered | 按条件过滤后剩下的行占 rows 的百分比 |
| **Extra** | 额外信息 |

### 6.1 type：从好到差

以下每个例子都是本机实测：

| type | 含义 | 例子 |
|---|---|---|
| `NULL` | 不用访问表 | `select 1;`、`select max(id) from tmp_ch07_user;`（Extra: `Select tables optimized away`） |
| `system` | 表里只有一行 | `select * from (select 1 as a) t;` |
| `const` | 主键或唯一索引等值查询，最多一行 | `where id = 10`、`where phone = '17799990009'` |
| `eq_ref` | 连接时，被驱动表按主键或唯一索引匹配 | `select * from tmp_ch07_user u join t_emp e on e.id = u.id;`（u 是 eq_ref） |
| `ref` | 普通索引等值查询，可能多行 | `where name = '白起'` |
| `range` | 索引范围扫描 | `where id between 3 and 8`、`where profession like '软件%'` |
| `index_merge` | 合并多个索引的结果 | `where id = 10 or name = '吕布'` |
| `index` | 扫描整个索引树 | `select name from tmp_ch07_user;`（Extra: `Using index`） |
| `ALL` | 全表扫描 | `where age = 27`（age 没有能用的索引） |

业务查询**至少要达到 `range`，最好是 `ref`**。看到 `ALL` 要警惕，看到 `index` 也不要以为走了索引就没问题，它是把整个索引从头扫到尾。

### 6.2 key_len 怎么算

| 列类型 | 字节数 |
|---|---|
| `int` | 4 |
| `bigint` | 8 |
| `tinyint` | 1 |
| `char(n)`，utf8mb4 | n × 4 |
| `varchar(n)`，utf8mb4 | n × 4 + 2（2 字节记录长度） |
| 允许 `null` | 再 + 1 |

实测验证：

| 索引列 | 定义 | 计算 | key_len |
|---|---|---|---|
| id | `int not null` | 4 | 4 |
| name | `varchar(10) not null` | 10×4 + 2 | 42 |
| phone（t_user） | `varchar(11) not null` | 11×4 + 2 | 46 |
| phone（tmp_ch07_big） | `char(11) not null` | 11×4 | 44 |
| profession | `varchar(20)` 可空 | 20×4 + 2 + 1 | 83 |
| + age | `tinyint unsigned` 可空 | 83 + 1 + 1 | 85 |
| + status | `char(1)` 可空 | 85 + 4 + 1 | 90 |

所以对联合索引 `(profession, age, status)`：key_len 是 83 说明只用了第 1 列，85 用了前 2 列，90 三列全用上了。

### 6.3 Extra 常见值

| Extra | 含义 | 好坏 |
|---|---|---|
| `Using index` | 覆盖索引，不回表 | 👍 |
| `Using index condition` | 索引下推 | 👍 |
| `Using where` | 在 Server 层按条件过滤 | 一般，和 type=ALL 一起出现就是全表扫描 |
| `Using filesort` | 不能利用索引排序，需要额外排序 | 👎 见[第 8 章](08-sql-optimization.md) |
| `Using temporary` | 用了临时表，常见于 `group by`、`distinct` | 👎 见[第 8 章](08-sql-optimization.md) |
| `Using index for skip scan` | 跳跃扫描（MySQL 8.0.13+） | 见下文 |
| `Select tables optimized away` | 直接从索引拿到结果，如 `max(id)` | 👍 |

## 7. 索引失效的场景

以下都在 `tmp_ch07_user` 上实测，联合索引是 `idx_profession_age_status(profession, age, status)`。

### 7.1 最左前缀法则

联合索引按 `profession → age → status` 的顺序排序：先按 profession 排，profession 相同再按 age 排，以此类推。所以**必须从最左边的列开始用，而且不能跳过中间的列**。

| 条件 | type | key_len | 说明 |
|---|---|---|---|
| `profession = '软件工程' and age = 31 and status = '0'` | ref | 90 | 三列全用 |
| `profession = '软件工程' and age = 31` | ref | 85 | 用前两列 |
| `profession = '软件工程'` | ref | 83 | 用第一列 |
| `profession = '软件工程' and status = '0'` | ref | 83 | 跳过 age，status 用不上（但能用索引下推） |
| `age = 31 and status = '0'` | **ALL** | — | 没有最左列，索引失效 |
| `status = '0' and age = 31 and profession = '软件工程'` | ref | 90 | **和 where 里的书写顺序无关**，优化器会调整 |

> 🟡 补充：MySQL 8.0.13 起有**跳跃扫描（skip scan）**。在 50 万行的表上，索引 `(city, age)`，执行 `select id, city, age from tmp_ch07_big where age = 30`，结果是 `type=range, Extra=Using index for skip scan`：最左列 city 只有 5 种值时，MySQL 会对每个 city 分别查 age = 30。但它只在覆盖索引、且最左列值很少时才生效，`select *` 依然是 `ALL`。**不要依赖它，设计索引时还是按最左前缀来。**

### 7.2 范围查询右边的列失效

| 条件 | type | key_len |
|---|---|---|
| `profession = '软件工程' and age > 30 and status = '0'` | range | **85**：status 没用上 |
| `profession = '软件工程' and age >= 31 and status = '0'` | range | **90**：三列都用上 |

`age > 30` 之后，满足条件的记录里 status 不再有序，所以用不上。业务允许时，**用 `>=`、`<=` 代替 `>`、`<`**。

### 7.3 在索引列上做运算或用函数

```sql
where substring(phone, 10, 2) = '15'   -- ALL
where id + 1 = 11                       -- ALL
```

索引里存的是 phone 的原始值，不是 `substring(phone, 10, 2)` 的结果。改写成对**常量**做运算：`where id = 11 - 1`。

日期是最常踩的坑：

```sql
where date(create_time) = '2024-01-01'                                     -- ❌ 失效
where create_time >= '2024-01-01' and create_time < '2024-01-02'           -- ✅ 走索引
```

### 7.4 字符串不加引号（隐式类型转换）

```sql
where phone = '17799990015'   -- const，走 idx_user_phone
where phone = 17799990015     -- ALL，possible_keys 有 idx_user_phone 但 key=NULL
```

字符串列和数字比较时，MySQL 会把**列的每个值都转成数字**再比较，相当于在索引列上用了函数。后端代码里，参数类型要和列类型一致（比如手机号在 Java 里用 `String`，不要用 `Long`）。

### 7.5 like 以 % 开头

```sql
where profession like '软件%'   -- range，走索引
where profession like '%工程'   -- ALL
```

索引按字符串从左往右排序，开头不确定就没法定位。需要「包含」查询时，考虑全文索引或搜索引擎。

### 7.6 or 的一边没有索引

```sql
where id = 10 or age = 23        -- ALL：age 没有能用的索引，反正要全表扫描，id 的索引也不用了
where id = 10 or name = '吕布'   -- index_merge：两边都有索引，分别查再合并
```

### 7.7 is null、is not null、!=

```sql
where profession is null       -- ref，走索引（这张表里 profession 没有 null 值）
where profession is not null   -- ALL
where name != '吕布'           -- ALL
```

这几个**不是一定失效**，取决于数据：`is not null` 和 `!=` 在这张表里会匹配到几乎所有行，走索引还要回表，不如直接全表扫描。如果大部分行是 null，`is not null` 反而可能走索引。

### 7.8 优化器认为全表扫描更快

MySQL 会估算成本：走索引要先查索引、再逐行回表；匹配的行太多时，还不如直接全表扫描。

```sql
-- tmp_ch07_user（t_user 的手机号从 17799990000 到 17799990023）
where phone > '17799990020'   -- range，匹配 3 行，走索引
where phone > '17799990001'   -- ALL，匹配 22 行，几乎全表，放弃索引
```

```sql
-- tmp_ch07_big（50 万行，city 有 5 种值，每种 10 万行）
where city = '北京'                     -- ref，走索引（匹配 20%）
where city in ('北京', '上海')           -- ALL（匹配 40%）
where city in ('北京', '上海', '广州')   -- ALL（匹配 60%）
```

前面 4.1 节的实测也说明了，要回表 10 万次时走索引确实比全表扫描慢。所以**区分度低的列（性别、状态、城市）单独建索引意义不大**。

### 7.9 失效场景速查

| 写法 | 结果 | 改法 |
|---|---|---|
| 联合索引不从最左列开始 | 失效 | 调整索引列顺序，或补上最左列条件 |
| 范围查询 `>` `<` | 右边的列失效 | 改用 `>=` `<=`；把范围查询的列放到联合索引最后 |
| 对索引列用函数、运算 | 失效 | 运算移到常量一侧 |
| 字符串列和数字比较 | 失效 | 参数类型和列类型保持一致 |
| `like '%xx'` | 失效 | `like 'xx%'`，或全文索引、搜索引擎 |
| `or` 一边没有索引 | 失效 | 两边都建索引，或改写成 `union` |
| 匹配行数太多 | 优化器放弃 | 用覆盖索引，或换区分度高的条件 |

## 8. 索引设计原则

### 8.1 七条设计原则

课程里的原文整理在 [04-performance.sql](../practice/04-performance.sql) 第 9 节，下面逐条解释原因。

**① 数据量较大、且查询比较频繁的表，才建索引**

- 为什么：数据少时全表扫描本来就很快。本章实验里 24 行的 `tmp_ch07_user` 上，优化器经常直接选 `ALL`；50 万行的 `tmp_ch07_big` 上，有没有索引是 0.10 秒和 0.001 秒的区别。
- 后端例子：`t_order`、`t_user`、`t_log` 这类会一直增长的表要认真设计索引；字典表、配置表、地区表只有几百行，有主键就够了。

**② 经常作为查询条件（`where`）、排序（`order by`）、分组（`group by`）的字段，建索引**

- 为什么：索引是排好序的，既能快速定位，也能直接按索引顺序取数据，省掉额外的排序和分组（`Using filesort`、`Using temporary`，见[第 8 章](08-sql-optimization.md)）。`join ... on` 的连接字段同理。
- 后端例子：「我的订单」列表 `where user_id = ? order by create_time desc`，就该建 `(user_id, create_time)`。最好的做法是**从代码里的 SQL 出发建索引**：把 Mapper 里的查询列出来，看每条走什么索引。

**③ 选区分度高的列建索引，尽量建唯一索引，区分度越高效率越高**

- 为什么：区分度 = `count(distinct 列) / count(*)`。区分度高，一次就能把范围缩得很小；区分度低，匹配行太多还要回表，优化器宁可全表扫描（见 7.8 节，实测 `tmp_ch07_big` 里 phone 区分度 1.0，city 只有 0.00001）。唯一索引最多匹配一行，`type` 是 `const`。
- 后端例子：手机号、订单号、身份证号、`user_id` 适合建索引；性别、状态、是否删除这类只有几个值的列，单独建索引基本没用。手机号、订单号这类业务上本来就不能重复的，建**唯一索引**，还能在数据库层面防止重复数据（比如防止重复下单）。

**④ 字符串类型的字段很长时，针对字段特点建前缀索引**

- 为什么：索引越长，一页能放的键越少，树越高，占的内存和磁盘越多。前缀索引只取前 n 个字符，按选择性选 n（见第 5 节）。代价是用不了覆盖索引。
- 后端例子：`email`、`url`、长文本标题。比如邮箱取前 5–10 个字符就足够区分，没必要对整个 `varchar(100)` 建索引。

**⑤ 尽量使用联合索引，减少单列索引**

- 为什么：查询时联合索引很多时候能覆盖要查的列（`Using index`），**不用回表**，节省存储空间，提高效率。而且一个联合索引 `(a, b, c)` 相当于同时有了 `(a)`、`(a, b)`、`(a, b, c)` 三个索引。多个单列索引在一条查询里通常只能用上一个。
- 后端例子：`where profession = ? and age = ?` 这类组合查询，建 `(profession, age, status)` 一个联合索引，比给 profession、age、status 各建一个单列索引更好。列表接口只查 `id, profession, age` 时，正好被覆盖。

**⑥ 要控制索引的数量，索引不是越多越好**

- 为什么：每个索引都是一棵 B+ 树，增删改时都要同步维护（见 8.3 节实测：多 4 个二级索引，插入从 2.1 秒变成 5.2 秒，索引占用比数据还大）。索引太多，优化器选错索引的概率也更大。
- 后端例子：单表一般不超过 5–6 个索引。上线新查询时先看能不能复用已有索引（调整列顺序、扩成联合索引），而不是每个接口加一个索引。定期用 `sys.schema_unused_indexes` 找没用过的索引。

**⑦ 如果索引列不能存储 null，建表时用 `not null` 约束**

- 为什么：优化器知道列里没有 null，就能更准确地判断该用哪个索引；`is null` 的判断、`count(列)` 也更简单。从 key_len 也能看出来：可空列多占 1 字节标记 null（`varchar(20)` 可空是 83，不可空是 82）。
- 后端例子：`user_id`、`status`、`create_time` 这类业务上必定有值的列，都写 `not null`，并给合适的 `default`。实体类里对应的字段也不应该是 null。

### 8.2 联合索引的列顺序

1. **等值查询的列放前面，范围查询的列放后面**。例如 `where user_id = ? and create_time > ?`，建 `(user_id, create_time)`。
2. **区分度高的列放前面**，能更快缩小范围。
3. 考虑能**服务尽量多的查询**：建了 `(a, b, c)`，就不需要再建 `(a)` 和 `(a, b)` 了。
4. 考虑**排序**：`where user_id = ? order by create_time desc`，建 `(user_id, create_time)` 可以同时满足查询和排序。

### 8.3 索引的代价

索引不是越多越好。在本机实测：同样 50 万行数据，表 A 只有主键，表 B 另外有 4 个二级索引：

| | 只有主键 | 主键 + 4 个二级索引 |
|---|---|---|
| 插入 50 万行 | 2.1 秒 | **5.2 秒** |
| 更新 10 万行的 name（name 上有索引） | 0.8 秒 | **1.4 秒** |
| 数据大小 | 32.6 MB | 32.6 MB |
| 索引大小 | 0 | **63.2 MB**（比数据还大） |

每次 `insert`、`update`、`delete` 都要同时维护所有相关的索引。一般建议**单表索引不超过 5–6 个**，定期清理没用的索引。

## 9. 小结

1. 索引是**排好序**的 B+ 树，三层就能存两千万行，查一行只读 3 页左右。
2. InnoDB 的数据按主键组织（聚集索引）；二级索引的叶子节点存的是主键，查整行要**回表**。
3. 要查的列都在索引里就不用回表（**覆盖索引**，`Using index`），所以少写 `select *`。
4. 看 `explain`：`type` 至少 `range`，`key` 不是 `NULL`，用 `key_len` 判断联合索引用了几列。
5. 记住失效场景：不满足最左前缀、范围查询右边的列、函数运算、隐式转换、`like '%xx'`、`or` 一边没索引。
6. 优化器会算成本，匹配的行太多时宁可全表扫描。区分度低的列单独建索引没用。
7. 优先建联合索引：等值列在前、范围列在后、区分度高的在前。
8. 索引会拖慢写入、占用空间，按需建，不要滥建。

---

上一章：[存储引擎 🟡](06-storage-engine.md) · [目录](../README.md) · 下一章：[SQL 优化 🟡](08-sql-optimization.md)

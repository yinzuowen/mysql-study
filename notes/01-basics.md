# 第 1 章 基础概念 🟢

> 本章练习：[schema.sql](../data/schema.sql)、[t_user.sql](../data/t_user.sql)

> 写后端时，几乎每个接口最终都在读写数据库。你会遇到这些问题：
> 金额加起来差了 0.01、用户昵称里的 emoji 存进去报错、同一个时间在两台服务器上查出来差 8 小时、`update` 忘了写 `where` 把整张表改了、给应用配的数据库账号权限太大。
> 这些都是基础没打牢导致的。本章讲清楚：数据库和表怎么建、字段类型怎么选、增删改怎么写才安全、账号权限怎么配。
>
> 本章的示例都在本机 MySQL（版本 26.10，`itcast` 库）上实际跑过，输出是真实结果。需要写数据的实验用的是临时表，做完已删除。

## 1. MySQL 是什么

- **关系型数据库**：数据存在一张张**表**里，表由**行**（一条记录）和**列**（一个字段）组成，表和表之间通过字段关联（比如员工表的 `dept_id` 对应部门表的 `id`）。
- **MySQL 的结构**：一个 MySQL 服务（实例）下有多个**数据库**，一个数据库里有多张**表**。

```
MySQL 实例
├── itcast（数据库）
│   ├── t_user（表）
│   ├── t_emp
│   └── t_dept
└── springboot_demo
```

- **客户端 / 服务端**：MySQL 服务在后台运行，监听 3306 端口。命令行 `mysql`、图形工具（DataGrip、Navicat）、你的后端程序（JDBC、MyBatis）都是客户端，通过网络连到服务端执行 SQL。

### 连接数据库

```bash
mysql -h 127.0.0.1 -P 3306 -u root -p   # -h 主机 -P 端口 -u 用户 -p 回车后输入密码
```

本机 Homebrew 装的 MySQL，默认的 socket 文件不可用时，要加 `-h 127.0.0.1` 走 TCP 连接。

后端程序里的连接串（JDBC）长这样：

```
jdbc:mysql://127.0.0.1:3306/itcast?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai
```

### SQL 的分类

| 分类 | 全称 | 作用 | 关键字 |
|---|---|---|---|
| DDL | Data Definition Language | 定义库、表、索引的结构 | `create`、`alter`、`drop`、`truncate` |
| DML | Data Manipulation Language | 增删改数据 | `insert`、`update`、`delete` |
| DQL | Data Query Language | 查询数据 | `select`（[第 2 章](02-single-table-query.md)） |
| DCL | Data Control Language | 管理用户和权限 | `create user`、`grant`、`revoke` |

SQL 语句以 `;` 结尾，关键字不区分大小写（`SELECT` 和 `select` 一样）。注释用 `-- 注释`（`--` 后面要有空格）、`# 注释` 或 `/* 注释 */`。

## 2. 数据库和表的操作（DDL）

### 数据库

```sql
show databases;                                         -- 查看所有数据库
create database if not exists itcast default charset utf8mb4;
use itcast;                                             -- 切换到这个库
select database();                                      -- 查看当前在哪个库
drop database if exists itcast;                         -- 删库，生产环境绝对不要随手执行
```

### 表

```sql
show tables;                     -- 当前库的所有表
desc t_user;                     -- 查看表结构
show create table t_user;        -- 查看完整的建表语句（含索引、字符集、注释）
```

建表：

```sql
create table t_user (
    id     int primary key auto_increment comment '主键',
    name   varchar(10) not null comment '姓名',
    phone  char(11)    not null comment '手机号',
    age    tinyint unsigned comment '年龄'
) engine = InnoDB default charset = utf8mb4 comment '用户表';
```

修改表结构（`alter table`），用一张临时表实测：

```sql
create table tmp_ch01_t (id int primary key, name varchar(10));
alter table tmp_ch01_t add column age tinyint unsigned comment '年龄' after name;  -- 加字段，放在 name 后面
alter table tmp_ch01_t modify name varchar(20) not null;                          -- 改类型或约束，不改名
alter table tmp_ch01_t change age user_age tinyint unsigned;                      -- 改名（同时要写类型）
alter table tmp_ch01_t rename to tmp_ch01_t2;                                     -- 改表名
desc tmp_ch01_t2;
```
```
+----------+------------------+------+-----+---------+-------+
| Field    | Type             | Null | Key | Default | Extra |
+----------+------------------+------+-----+---------+-------+
| id       | int              | NO   | PRI | NULL    |       |
| name     | varchar(20)      | NO   |     | NULL    |       |
| user_age | tinyint unsigned | YES  |     | NULL    |       |
+----------+------------------+------+-----+---------+-------+
```

```sql
alter table tmp_ch01_t2 drop column user_age;   -- 删字段，数据一起没了
drop table if exists tmp_ch01_t2;              -- 删表
```

> ⚠️ 线上大表执行 `alter table` 会加元数据锁，可能把整张表卡住，详见[第 9 章 锁](09-lock.md)。

## 3. 数据类型怎么选

### 3.1 整数

| 类型 | 字节 | 有符号范围 | 无符号（unsigned）范围 | 典型用途 |
|---|---|---|---|---|
| `tinyint` | 1 | -128 ~ 127 | 0 ~ 255 | 状态、类型、年龄 |
| `smallint` | 2 | -32768 ~ 32767 | 0 ~ 65535 | |
| `int` | 4 | 约 ±21 亿 | 0 ~ 约 42 亿 | 数量 |
| `bigint` | 8 | 约 ±922 亿亿 | | 主键 ID、金额（以分为单位） |

超出范围会直接报错（严格模式下，MySQL 8 默认开启）：

```sql
create table tmp_ch01_num (a tinyint, b tinyint unsigned, f float, d double, m decimal(10,2));
insert into tmp_ch01_num values (127, 255, 0.1, 0.1, 0.1);   -- 正好在范围内，成功
insert into tmp_ch01_num(a) values (128);
-- ERROR 1264 (22003): Out of range value for column 'a' at row 1
insert into tmp_ch01_num(b) values (-1);
-- ERROR 1264 (22003): Out of range value for column 'b' at row 1
```

- `unsigned` 表示不允许负数，范围翻倍。年龄、数量这类不会为负的字段可以加。
- `int(11)` 里的 11 **不是长度限制**，只是旧版本的显示宽度，MySQL 8 已经不推荐写了。

### 3.2 小数：金额必须用 decimal

`float`、`double` 是二进制浮点数，很多十进制小数存不准；`decimal(M, D)` 是精确的十进制，M 是总位数，D 是小数位数。

```sql
select f + 0.2 float_sum, d + 0.2 double_sum, m + 0.2 decimal_sum,
       (f + 0.2) = 0.3 f_eq, (m + 0.2) = 0.3 m_eq
from tmp_ch01_num;   -- f、d、m 存的都是 0.1
```
```
+---------------------+---------------------+-------------+------+------+
| float_sum           | double_sum          | decimal_sum | f_eq | m_eq |
+---------------------+---------------------+-------------+------+------+
| 0.30000000149011613 | 0.30000000000000004 |        0.30 |    0 |    1 |
+---------------------+---------------------+-------------+------+------+
```

0.1 + 0.2 用 `float` 算出来不等于 0.3。把 0.1 累加 10 次：`float` 得到 `1.0000000149011612`，`decimal` 得到 `1.00`。

`decimal` 小数位超出时会**四舍五入**，只给一个提示，不报错：

```sql
insert into tmp_ch01_num(m) values (123.456);   -- 存进去的是 123.46
-- Note 1265: Data truncated for column 'm' at row 1
```

**金额用 `decimal(10, 2)`**，或者用 `bigint` 存「分」（后端代码里也别用 `double` 算钱，Java 用 `BigDecimal`）。

### 3.3 字符串

| 类型 | 说明 | 适合 |
|---|---|---|
| `char(n)` | 定长，最多 n 个字符，不足补空格，读取时去掉尾部空格 | 长度固定：手机号、身份证号、学号 |
| `varchar(n)` | 变长，最多 n 个字符，按实际长度存 | 长度不固定：姓名、邮箱、地址 |
| `text` | 长文本，最大 64KB | 文章内容、备注 |

`n` 是**字符数**，不是字节数。实测：

```sql
create table tmp_ch01_str (c char(5), v varchar(5));
insert into tmp_ch01_str values ('ab  ', 'ab  ');   -- 都带两个尾部空格
select concat('[', c, ']') c, concat('[', v, ']') v, length(c), length(v) from tmp_ch01_str;
```
```
+------+--------+-----------+-----------+
| c    | v      | length(c) | length(v) |
+------+--------+-----------+-----------+
| [ab] | [ab  ] |         2 |         4 |
+------+--------+-----------+-----------+
```

`char` 把尾部空格去掉了，`varchar` 原样保留。

```sql
select length('中文'), char_length('中文');   -- 6 和 2：utf8mb4 下一个汉字占 3 个字节
insert into tmp_ch01_str values ('abcdef', 'x');
-- ERROR 1406 (22001): Data too long for column 'c' at row 1
```

长度不要无脑写 `varchar(255)`，按业务给一个合理的上限，既是校验也省内存（排序、临时表会按定义长度分配空间）。

### 3.4 日期时间：datetime 和 timestamp

| 类型 | 范围 | 时区 | 说明 |
|---|---|---|---|
| `date` | 1000-01-01 ~ 9999-12-31 | — | 只有日期，如生日 |
| `datetime` | 1000-01-01 ~ 9999-12-31 | 不转换 | 存什么就是什么 |
| `timestamp` | 1970-01-01 ~ **2038-01-19 03:14:07 UTC** | 自动转换 | 存的时候转成 UTC，读的时候转回当前会话时区 |

时区实测：在 `+08:00` 时区存入同一个时间，再切到 `+00:00` 查询：

```sql
create table tmp_ch01_time (dt datetime, ts timestamp);
set time_zone = '+08:00';
insert into tmp_ch01_time values ('2026-11-20 10:00:00', '2026-11-20 10:00:00');
set time_zone = '+00:00';
select dt, ts from tmp_ch01_time;
```
```
+---------------------+---------------------+
| dt                  | ts                  |
+---------------------+---------------------+
| 2026-11-20 10:00:00 | 2026-11-20 02:00:00 |   <- timestamp 按新时区换算了，少了 8 小时
+---------------------+---------------------+
```

2038 年问题实测（`+00:00` 时区下）：

```sql
insert into tmp_ch01_time(ts) values ('2038-01-19 03:14:07');   -- 成功，这是上限
insert into tmp_ch01_time(ts) values ('2038-01-19 03:14:08');
-- ERROR 1292 (22007): Incorrect datetime value: '2038-01-19 03:14:08' for column 'ts' at row 1
```

**建议：统一用 `datetime`**，并且让数据库、应用服务器、JDBC 连接串（`serverTimezone`）用同一个时区。

### 3.5 JSON

MySQL 5.7 起支持 `json` 类型，会校验格式，可以按路径取值：

```sql
create table tmp_ch01_json (id int primary key, info json);
insert into tmp_ch01_json values (1, '{"name": "吕布", "tags": ["武将", "三国"], "age": 23}');
select info->'$.name' a, info->>'$.name' b, info->>'$.tags[0]' tag0, json_extract(info, '$.age') age
from tmp_ch01_json;
```
```
+----------+--------+--------+------+
| a        | b      | tag0   | age  |
+----------+--------+--------+------+
| "吕布"   | 吕布   | 武将   | 23   |
+----------+--------+--------+------+
```

`->` 返回带引号的 JSON 值，`->>` 返回去掉引号的文本。格式不对会直接报错：

```sql
insert into tmp_ch01_json values (2, '{bad json}');
-- ERROR 3140 (22032): Invalid JSON text: "Missing a name for object member." ...
```

适合存结构不固定的扩展信息（如商品的规格参数）。经常要按某个字段查询、排序的，还是拆成普通列。

### 3.6 类型选择速查

| 场景 | 推荐 |
|---|---|
| 主键 | `bigint`（`int` 最大约 21 亿，业务表直接用 `bigint` 省心） |
| 状态、类型、性别 | `tinyint`，在注释里写清每个值的含义 |
| 金额 | `decimal(10, 2)` 或 `bigint` 存分 |
| 手机号、身份证号 | `char(11)`、`char(18)`，**不要用整数**（会丢开头的 0，也不能参与计算） |
| 姓名、邮箱 | `varchar(n)` |
| 创建/更新时间 | `datetime` |
| 长文本 | `text` |

## 4. 字符集与排序规则

### utf8 和 utf8mb4

MySQL 里的 `utf8` 其实是 `utf8mb3`：每个字符最多 3 个字节，**存不了 emoji** 和部分生僻字（它们要 4 个字节）。实测：

```sql
create table tmp_ch01_u8 (s varchar(10)) charset utf8;
show create table tmp_ch01_u8;   -- 实际创建出来是 DEFAULT CHARSET=utf8mb3

create table tmp_ch01_cs3 (s varchar(10)) charset utf8mb3;
insert into tmp_ch01_cs3 values ('你好😀');
-- ERROR 1366 (HY000): Incorrect string value: '\xF0\x9F\x98\x80' for column 's' at row 1

create table tmp_ch01_cs4 (s varchar(10)) charset utf8mb4;
insert into tmp_ch01_cs4 values ('你好😀');
select s, length(s), char_length(s) from tmp_ch01_cs4;
```
```
+------------+-----------+----------------+
| s          | length(s) | char_length(s) |
+------------+-----------+----------------+
| 你好😀     |        10 |              3 |   <- 2 个汉字 × 3 字节 + 1 个 emoji × 4 字节
+------------+-----------+----------------+
```

**一律用 `utf8mb4`**。本机 MySQL 8 默认就是：

```sql
select @@character_set_server, @@collation_server;   -- utf8mb4、utf8mb4_0900_ai_ci
```

### 排序规则（collation）：比较时是否区分大小写

排序规则决定字符串怎么比较、怎么排序。默认的 `utf8mb4_0900_ai_ci`：`ai` = 不区分重音，`ci` = **不区分大小写**（case insensitive）。

```sql
select 'abc' = 'ABC' ci,
       'abc' = 'ABC' collate utf8mb4_bin bin,
       'a' = 'a ' trailing_space;
```
```
+----+------+----------------+
| ci | bin  | trailing_space |
+----+------+----------------+
|  1 |    0 |              0 |
+----+------+----------------+
```

所以 `where email like 'LVBU%'` 能查到 `lvbu666@163.com`。需要区分大小写的字段（如验证码、区分大小写的用户名），列上指定 `collate utf8mb4_bin`。

## 5. 增删改（DML）

下面用一张临时用户表演示，`phone` 有唯一约束：

```sql
create table tmp_ch01_user (
    id          int primary key auto_increment,
    phone       char(11)    not null unique,
    name        varchar(10) not null,
    login_count int         not null default 0
);
```

### 5.1 insert 的几种写法

```sql
insert into tmp_ch01_user (phone, name) values ('13800000001', '张三');                          -- 指定字段（推荐）
insert into tmp_ch01_user (phone, name) values ('13800000002', '李四'), ('13800000003', '王五');  -- 一次插多行
insert into tmp_ch01_user values (null, '13800000004', '赵六', 0);                               -- 不写字段名，要按顺序给全所有列
insert into tmp_ch01_user set phone = '13800000005', name = '孙七';                              -- MySQL 特有写法
```

- **始终写上字段名**。不写的话，表结构一加字段，这条 SQL 就报错了。
- 批量插入用一条 `insert ... values (...), (...)`，比循环插入快得多。
- 自增列传 `null` 或不写，由数据库生成。

插入重复的手机号：

```sql
insert into tmp_ch01_user (phone, name) values ('13800000001', '张三三');
-- ERROR 1062 (23000): Duplicate entry '13800000001' for key 'tmp_ch01_user.phone'
```

### 5.2 不存在就插入，存在就更新

```sql
insert into tmp_ch01_user (phone, name, login_count) values ('13800000003', '王五五', 1) as new
on duplicate key update name = new.name, login_count = tmp_ch01_user.login_count + 1;
select row_count();   -- 2：表示走了更新；1 表示新插入
```

- 主键或唯一索引冲突时执行 `update` 部分，否则正常插入。适合「有就累加，没有就新建」的场景，比如统计登录次数。
- 旧写法 `name = values(name)` 还能用，但实测会提示 `'VALUES function' is deprecated`，新代码用 `as 别名` 的写法。
- `insert ignore`：冲突时**跳过这一行**，只给一个 warning，不报错。容易悄悄丢数据，慎用。

### 5.3 自增 ID 不连续是正常的

上面插入了 5 行、失败了 1 次、更新了几次、又新插 1 行，结果新行的 id 是 **10**，不是 6：

```
+----+-------------+-----------+-------------+
| id | phone       | name      | login_count |
+----+-------------+-----------+-------------+
|  1 | 13800000001 | 张三三    |           1 |
|  ...                                        |
|  5 | 13800000005 | 孙七      |           0 |
| 10 | 13800000009 | 新用户    |           1 |
+----+-------------+-----------+-------------+
```

插入失败、`on duplicate key update`、事务回滚都会消耗自增值。**不要用自增 id 是否连续来判断数据有没有丢**，也不要把它当成「第几个用户」展示给用户。

### 5.4 update 和 delete

```sql
update tmp_ch01_user set login_count = login_count + 1 where id = 1;   -- row_count() = 1
update tmp_ch01_user set login_count = login_count where id = 1;       -- row_count() = 0：值没变，不算影响
delete from tmp_ch01_user where id = 999;                              -- row_count() = 0：没有匹配的行
```

- `row_count()` 是受影响的行数。后端框架里 `update` 的返回值就是它，**乐观锁就靠判断它是不是 0**（见[第 9 章](09-lock.md)）。
- MySQL 的 `update`、`delete` 可以带 `order by` 和 `limit`，用于分批处理：

```sql
update tmp_ch01_user set login_count = 99 where login_count = 0 order by id limit 1;   -- 只改 id 最小的那一行
delete from t_log where create_time < '2026-01-01' limit 1000;                          -- 大批量删除时每次删 1000 行，分多次执行
```

> ⚠️ **`update`、`delete` 一定要带 `where`**。执行前先用同样的 `where` 写一条 `select` 确认影响哪些行。

命令行里可以开安全模式，没有走索引的 `where` 就拒绝执行：

```sql
set sql_safe_updates = 1;
update tmp_ch01_user set name = 'x';
-- ERROR 1175 (HY000): You are using safe update mode and you tried to update a table without a WHERE that uses a KEY column.
```

### 5.5 delete 和 truncate

| | `delete from 表` | `truncate table 表` |
|---|---|---|
| 类型 | DML | DDL |
| 能否带 where | 能 | 不能，只能清空整张表 |
| 能否回滚 | 能 | **不能** |
| 自增 id | 继续往后增长 | **重置为 1** |
| 速度 | 逐行删除，慢 | 直接重建表，快 |

实测：

```sql
delete from tmp_ch01_user;
insert into tmp_ch01_user (phone, name) values ('13900000000', 'delete后');     -- id = 3，接着之前的往下
truncate table tmp_ch01_user;
insert into tmp_ch01_user (phone, name) values ('13900000000', 'truncate后');   -- id = 1，重置了

begin; delete from tmp_ch01_user; rollback;     -- 回滚后还剩 1 行
begin; truncate table tmp_ch01_user; rollback;  -- 回滚后 0 行：truncate 会隐式提交，回滚无效
```

## 6. 用户与权限（DCL）

后端程序连数据库**不要用 root**，给它建一个专用账号，只给需要的权限（最小权限原则）。

```sql
create user 'tmp_ch01_app'@'localhost' identified by 'Test@123456';
grant select, insert, update, delete on itcast.* to 'tmp_ch01_app'@'localhost';
show grants for 'tmp_ch01_app'@'localhost';
```
```
+----------------------------------------------------------------------------------+
| Grants for tmp_ch01_app@localhost                                                |
+----------------------------------------------------------------------------------+
| GRANT USAGE ON *.* TO `tmp_ch01_app`@`localhost`                                 |
| GRANT SELECT, INSERT, UPDATE, DELETE ON `itcast`.* TO `tmp_ch01_app`@`localhost` |
+----------------------------------------------------------------------------------+
```

用这个账号登录后，能正常查询，但删表被拒绝：

```
ERROR 1142 (42000): DROP command denied to user 'tmp_ch01_app'@'localhost' for table 'tmp_ch01_num'
```

收回权限、删除用户：

```sql
revoke delete on itcast.* from 'tmp_ch01_app'@'localhost';   -- 之后执行 delete 报 DELETE command denied
drop user 'tmp_ch01_app'@'localhost';
```

- `'用户名'@'主机'` 是一个整体：`'app'@'localhost'` 只能本机登录，`'app'@'%'` 可以从任意主机登录，`'app'@'10.0.0.%'` 限定网段。
- `itcast.*` 表示 itcast 库的所有表，`*.*` 表示所有库。
- 常见分配：应用账号只给业务库的增删改查；只读账号（报表、数据分析）只给 `select`；改表结构由 DBA 或发布流程用单独的账号执行。

## 7. null 的坑

`null` 表示「未知」，不是 0，也不是空字符串。和 `null` 做比较、运算，结果都是 `null`：

```sql
select null = null, null is null, null <> 1, 1 + null, concat('a', null), ifnull(null, 0), coalesce(null, null, 3);
```
```
+-------------+--------------+-----------+----------+-------------------+-----------------+-------------------------+
| null = null | null is null | null <> 1 | 1 + null | concat('a', null) | ifnull(null, 0) | coalesce(null, null, 3) |
+-------------+--------------+-----------+----------+-------------------+-----------------+-------------------------+
|        NULL |            1 |      NULL |     NULL | NULL              |               0 |                       3 |
+-------------+--------------+-----------+----------+-------------------+-----------------+-------------------------+
```

在 `itcast.t_emp` 上实测（7 名员工，熊杨的 `dept_id` 是 `null`，其余分布在 1–5 号部门）：

| 查询 | 结果 | 说明 |
|---|---|---|
| `where dept_id = null` | 0 行 | ❌ 永远查不到，要用 `is null` |
| `where dept_id is null` | 1 行 | ✅ |
| `where dept_id <> 1` | 4 行 | 熊杨**不在结果里**，`null <> 1` 不是真 |
| `where dept_id not in (1, null)` | 0 行 | ❌ `not in` 的列表里有 `null`，整个条件永远不成立 |
| `count(*)` / `count(dept_id)` | 7 / 6 | `count(列)` 不统计 `null` |

建议：

- 字段尽量设成 `not null` 并给默认值（数字给 0，字符串给 `''`），少和 `null` 打交道。
- 判断用 `is null` / `is not null`；需要默认值时用 `ifnull(列, 默认值)` 或 `coalesce(...)`。
- `not in (子查询)` 时，确保子查询结果里不会有 `null`，或者改用 `not exists`。

## 8. 小结

1. 一个 MySQL 实例里有多个库，一个库里有多张表；SQL 分为 DDL、DML、DQL、DCL。
2. 主键用 `bigint`，金额用 `decimal`（`float` 实测 0.1 + 0.2 ≠ 0.3），手机号用 `char`，时间用 `datetime`。
3. 字符集一律 `utf8mb4`，MySQL 的 `utf8` 存不了 emoji；默认排序规则不区分大小写。
4. `insert` 始终写字段名；批量插入用一条多值 `insert`；「有则更新无则插入」用 `on duplicate key update`。
5. `update`、`delete` 一定要带 `where`，先 `select` 确认；`truncate` 不能回滚、会重置自增 id。
6. 自增 id 会有空洞，是正常现象。
7. 应用不要用 root 连库，按最小权限原则建专用账号。
8. 判断 `null` 用 `is null`；`<>`、`not in`、`count(列)` 都会被 `null` 影响。

---

[目录](../README.md) · 下一章：[单表查询 🟢](02-single-table-query.md)

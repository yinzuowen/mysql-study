# 第 4 章 约束与表设计 🟢

> 为什么要学：表结构一旦上线、有了数据，再改就很麻烦。字段类型选错（金额用了 `float`）、少了唯一约束（同一个手机号注册了两次）、主键用了 UUID（插入越来越慢），都是上线后才暴露、改起来要停服或迁移数据的问题。
> 作为后端开发，你经常要自己设计业务表。本章讲清楚：约束怎么用、主键怎么选、表怎么拆、业务表有哪些约定俗成的写法。
>
> 本章的报错和结果都在本机 MySQL 上实际跑过。实验用的是临时建的 `tmp_ch04_*` 表，做完已删除，不影响 `itcast` 里的其他表。

## 1. 约束：让数据库帮你挡住脏数据

约束是加在字段上的规则，违反规则的数据**写不进去**。代码里的校验可能有漏洞、可能有人直接改库，约束是最后一道防线。

| 约束 | 关键字 | 作用 |
|---|---|---|
| 非空 | `not null` | 不能为 `NULL` |
| 唯一 | `unique` | 不能重复 |
| 主键 | `primary key` | 非空 + 唯一，每张表一个 |
| 默认值 | `default` | 不传值时用默认值 |
| 检查 | `check` | 满足条件才能写入（MySQL 8.0.16 起生效） |
| 外键 | `foreign key` | 值必须在另一张表里存在 |

### 1.1 实测：每种约束违反时的报错

```sql
create table tmp_ch04_user (
    id       bigint primary key auto_increment,
    username varchar(20) not null,
    phone    char(11) not null,
    age      tinyint unsigned check (age between 1 and 120),
    status   tinyint not null default 1,
    unique key uk_phone (phone)
);
insert into tmp_ch04_user (username, phone, age) values ('张三', '13800000001', 20);
```

然后依次插入违反约束的数据：

| 插入的数据 | 报错 |
|---|---|
| `username` 传 `null` | `ERROR 1048: Column 'username' cannot be null` |
| 不传 `username`（没有默认值） | `ERROR 1364: Field 'username' doesn't have a default value` |
| `phone` 和张三重复 | `ERROR 1062: Duplicate entry '13800000001' for key 'tmp_ch04_user.uk_phone'` |
| `id` 传 1，和张三重复 | `ERROR 1062: Duplicate entry '1' for key 'tmp_ch04_user.PRIMARY'` |
| `age` 传 200 | `ERROR 3819: Check constraint 'tmp_ch04_user_chk_1' is violated.` |
| `age` 传 0 | `ERROR 3819: Check constraint 'tmp_ch04_user_chk_1' is violated.` |
| `username` 传 21 个汉字 | `ERROR 1406: Data too long for column 'username' at row 1` |

**后端开发要记住的错误码**：`1062`（唯一约束冲突）最常见。比如注册时两个请求同时用同一个手机号提交，代码里「先查有没有、再插入」挡不住并发，只有唯一索引能挡住。代码里捕获 `1062`（Spring 里是 `DuplicateKeyException`），返回「手机号已注册」。

> 上面「数据太长报错」依赖 `sql_mode` 里的 `STRICT_TRANS_TABLES`（本机默认开启）。如果关掉严格模式，MySQL 会**静默截断**数据并只给一个警告，这非常危险，生产环境一定要开严格模式。

### 1.2 not null 和 default

- 能不为 `NULL` 的字段尽量都加 `not null`，再配一个合理的 `default`。
- `NULL` 会带来很多麻烦：`count(列)` 不计数、`not in` 查不出结果（见[第 3 章 3.3](03-multi-table-query.md)）、`= NULL` 永远不成立要写 `is null`、代码里要判空。
- 字符串用 `default ''`，数字用 `default 0`，状态用一个明确的初始值。

```sql
status tinyint not null default 1 comment '状态：0 禁用，1 启用'
```

### 1.3 unique：允许多个 NULL

```sql
create table tmp_ch04_n (id int primary key auto_increment, email varchar(50) unique);
insert into tmp_ch04_n (email) values (null), (null), ('a@b.com');   -- 成功
```
```
+----+---------+
| id | email   |
+----+---------+
|  1 | NULL    |
|  2 | NULL    |
|  3 | a@b.com |
+----+---------+
```

唯一约束只管非 `NULL` 的值，多个 `NULL` 不算重复。如果「没填邮箱」和「邮箱重复」要区分开，这正好是想要的效果；否则就加上 `not null`。

### 1.4 check

```sql
age tinyint unsigned check (age between 1 and 120)
```

MySQL 8.0.16 之前，`check` 能写但**不生效**。现在生效了，但业务上一般还是在代码里校验（报错信息更友好），`check` 当兜底。

## 2. 外键

外键保证「子表的值在父表里一定存在」。比如员工的 `dept_id` 必须是一个存在的部门 `id`。

```sql
create table tmp_ch04_dept (id int primary key, name varchar(20) not null);
create table tmp_ch04_emp (
    id      int primary key,
    name    varchar(20),
    dept_id int,
    constraint fk_tmp_ch04_emp_dept foreign key (dept_id) references tmp_ch04_dept(id)
);
insert into tmp_ch04_dept values (1, '研发部'), (2, '市场部');
insert into tmp_ch04_emp values (1, '张三', 1), (2, '李四', 1), (3, '王五', 2);
```

### 2.1 默认行为：不允许（restrict）

| 操作 | 结果 |
|---|---|
| 插入员工，`dept_id = 99`（部门不存在） | `ERROR 1452: Cannot add or update a child row: a foreign key constraint fails` |
| 删除研发部（还有员工） | `ERROR 1451: Cannot delete or update a parent row: a foreign key constraint fails` |
| 把研发部的 `id` 改成 10 | `ERROR 1451`，同上 |

### 2.2 on delete / on update 的几种行为

| 行为 | 父表删除或更新时，子表怎么办 |
|---|---|
| `restrict` / `no action`（默认） | 子表有关联数据就不允许操作 |
| `cascade` | 子表跟着删除或更新 |
| `set null` | 子表的外键字段设为 `NULL` |

**cascade 实测**：

```sql
alter table tmp_ch04_emp drop foreign key fk_tmp_ch04_emp_dept;
alter table tmp_ch04_emp add constraint fk_tmp_ch04_emp_dept
    foreign key (dept_id) references tmp_ch04_dept(id) on update cascade on delete cascade;

update tmp_ch04_dept set id = 10 where id = 1;   -- 员工的 dept_id 跟着变成 10
delete from tmp_ch04_dept where id = 10;         -- 张三、李四被一起删掉了
```
```
-- update 之后                      -- delete 之后
| 1 | 张三 | 10 |                    | 3 | 王五 | 2 |
| 2 | 李四 | 10 |
| 3 | 王五 |  2 |
```

删一个部门，员工数据就**静悄悄地没了**，也不会有任何提示。

**set null 实测**：

```sql
-- 改成 on delete set null 后
delete from tmp_ch04_dept where id = 2;
```
```
| 3 | 王五 | NULL |      -- 王五还在，部门变成了 NULL
```

`itcast` 里的 `t_emp` 就是这么建的（`ON DELETE SET NULL ON UPDATE SET NULL`），这也是为什么熊杨的 `dept_id` 是 `NULL`。

### 2.3 为什么互联网业务通常不用外键

阿里巴巴 Java 开发手册明确规定：「不得使用外键与级联，一切外键概念必须在应用层解决」。原因：

1. **性能**：每次写子表都要去父表检查，还会给父表的行加共享锁，高并发时容易锁等待、死锁。
2. **级联操作不可控**：`cascade` 一删一大片，不走代码逻辑，没有日志、不触发业务事件（比如发消息、清缓存）。
3. **分库分表后用不了**：父表和子表可能不在同一个库。
4. **数据迁移、修数据麻烦**：导入数据要按依赖顺序，删表要先删外键（实测：直接删父表报 `ERROR 3730: Cannot drop table ... referenced by a foreign key constraint`）。

不用外键，**关联关系要在代码里保证**：插入员工前校验部门存在，删部门前检查有没有员工。外键**字段**（`dept_id`）照样要有，并且要**建普通索引**，因为连接查询要用到。

> 学校作业、内部管理系统、数据量小的项目，用外键保证数据一致性完全没问题。

## 3. 主键

### 3.1 每张表都要有主键

InnoDB 的数据就是按主键组织存放的（聚集索引，见[第 7 章](07-index.md)）。没有主键时，InnoDB 会自己生成一个隐藏的 6 字节 row_id，你用不上它，还浪费空间。**每张表都显式定义主键。**

### 3.2 自增主键的 id 会不连续

```sql
create table tmp_ch04_ai (id int primary key auto_increment, phone char(11) not null unique);
insert into tmp_ch04_ai (phone) values ('13800000001');   -- id = 1
insert into tmp_ch04_ai (phone) values ('13800000001');   -- 唯一约束冲突，失败
insert into tmp_ch04_ai (phone) values ('13800000002');   -- id = 3，2 被跳过了
begin;
insert into tmp_ch04_ai (phone) values ('13800000003');   -- 拿到 id = 4
rollback;                                                  -- 回滚，4 不会还回去
insert into tmp_ch04_ai (phone) values ('13800000004');   -- id = 5
```
```
+----+-------------+
| id | phone       |
+----+-------------+
|  1 | 13800000001 |
|  3 | 13800000002 |
|  5 | 13800000004 |
+----+-------------+
```

原因：自增值在插入时**先分配**，为了并发性能，分配出去的值不会因为插入失败或事务回滚而收回。所以：

- **不要用自增 id 做业务含义**，比如「id 连续所以总共有多少订单」「用 id 生成连续的编号」。
- 要连续编号（发票号等），另外设计编号生成逻辑。

### 3.3 主键怎么选：自增 vs UUID vs 雪花 ID

| | 自增 id | UUID | 雪花 ID（Snowflake） |
|---|---|---|---|
| 样子 | `1, 2, 3...` | `2e7b1eac-e4e0-11f1-bfb9-fdb699dc8504`（实测 `select uuid()`） | `1859284031234560001` |
| 类型 | `bigint`，8 字节 | `char(36)`，36 字节 | `bigint`，8 字节 |
| 有序 | ✅ 递增 | ❌ 无序 | ✅ 趋势递增 |
| 插入性能 | 好，总是追加到最后 | 差，随机插入导致页分裂 | 好 |
| 二级索引大小 | 小 | 大（每个二级索引都存一份主键） | 小 |
| 分库分表 | ❌ 多个库会重复 | ✅ 全局唯一 | ✅ 全局唯一 |
| 暴露业务量 | ❌ 能从 id 推算订单量 | ✅ | 基本 ✅ |

建议：

- **单库单表**：用 `bigint` 自增主键，简单高效。
- **分库分表、多个服务各自生成 id**：用雪花 ID（在应用里生成，如 MyBatis-Plus 的 `IdType.ASSIGN_ID`、Hutool 的 `IdUtil.getSnowflakeNextId()`）。
- **不要用 UUID 做主键**。需要对外暴露的随机编号，单独加一个字段（如 `order_no`）加唯一索引。

## 4. 数据库设计范式

范式是表设计的基本规则，目的是**减少冗余、避免数据不一致**。实际工作中掌握前三个就够了。

### 4.1 反例：一张大表存所有东西

| 订单号 | 用户名 | 用户手机 | 商品 | 单价 | 数量 |
|---|---|---|---|---|---|
| NO001 | 张三 | 13800000001 | 键盘,鼠标 | 199,99 | 1,2 |
| NO002 | 张三 | 13800000001 | 显示器 | 1299 | 1 |

问题：
- 一个格子里存了多个值（`键盘,鼠标`），没法按商品查询、统计。
- 张三改手机号，要改所有订单，漏改一条数据就不一致了。

### 4.2 第一范式（1NF）：每个字段不可再分

一个字段只存一个值。`键盘,鼠标` 违反了 1NF，要拆成多行：

| 订单号 | 用户名 | 用户手机 | 商品 | 单价 | 数量 |
|---|---|---|---|---|---|
| NO001 | 张三 | 13800000001 | 键盘 | 199 | 1 |
| NO001 | 张三 | 13800000001 | 鼠标 | 99 | 2 |
| NO002 | 张三 | 13800000001 | 显示器 | 1299 | 1 |

> 「地址」要不要拆成省、市、区？看业务：要按城市统计就拆，只用来显示就不拆。

### 4.3 第二范式（2NF）：非主键字段要依赖整个主键

上表的主键是（订单号, 商品）。但「用户名」只依赖订单号，和商品无关。违反 2NF → 拆成订单表和订单明细表：

- 订单表：订单号、用户名、用户手机
- 订单明细表：订单号、商品、单价、数量

### 4.4 第三范式（3NF）：非主键字段不能依赖其他非主键字段

订单表里「用户手机」依赖的是「用户名」（用户），而不是订单号。违反 3NF → 再拆出用户表：

- 用户表：用户 id、用户名、手机
- 订单表：订单号、用户 id
- 订单明细表：订单号、商品 id、单价、数量

现在张三改手机号，只要改用户表一行。

### 4.5 适当反范式：用冗余换性能

完全遵守范式，查询时就要连很多张表。实际工作中会**有意识地冗余**一些字段：

| 冗余字段 | 原因 |
|---|---|
| 订单明细里存 `goods_name`、`price` | **快照**：商品以后改名、改价，历史订单不能跟着变。这是业务要求，不是偷懒 |
| 订单表里存 `total_amount` | 列表页不用每次去明细表 `sum` |
| 文章表里存 `comment_count` | 不用每次 `count` 评论表 |

冗余的代价是要保证一致：比如新增评论时同时更新 `comment_count`，放在同一个事务里。

## 5. 表之间的关系怎么建

### 5.1 一对多：在「多」的一方加关联字段

一个用户有多个订单，一个订单有多条明细：

```sql
create table t_order (
    id           bigint         primary key auto_increment comment '主键',
    order_no     varchar(32)    not null comment '订单号',
    user_id      bigint         not null comment '下单用户ID',
    total_amount decimal(10, 2) not null comment '订单总金额',
    status       tinyint        not null default 0 comment '状态：0 待支付，1 已支付，2 已发货，3 已完成，4 已取消',
    is_deleted   tinyint        not null default 0 comment '逻辑删除：0 未删除，1 已删除',
    create_time  datetime       not null default current_timestamp comment '创建时间',
    update_time  datetime       not null default current_timestamp on update current_timestamp comment '更新时间',
    unique key uk_order_no (order_no),
    key idx_user_id (user_id)
) engine = InnoDB default charset = utf8mb4 comment '订单表';

create table t_order_item (
    id         bigint         primary key auto_increment comment '主键',
    order_id   bigint         not null comment '订单ID',
    goods_id   bigint         not null comment '商品ID',
    goods_name varchar(64)    not null comment '商品名称（下单时的快照）',
    price      decimal(10, 2) not null comment '下单时的单价',
    quantity   int            not null comment '购买数量',
    key idx_order_id (order_id)
) engine = InnoDB default charset = utf8mb4 comment '订单明细表';
```

关联字段（`user_id`、`order_id`）不建外键，但**一定要建索引**。

### 5.2 多对多：建中间表

一个用户有多个角色，一个角色有多个用户：

```sql
create table t_role (
    id   bigint      primary key auto_increment comment '主键',
    name varchar(32) not null comment '角色名'
) engine = InnoDB default charset = utf8mb4 comment '角色表';

create table t_user_role (
    id      bigint primary key auto_increment comment '主键',
    user_id bigint not null comment '用户ID',
    role_id bigint not null comment '角色ID',
    unique key uk_user_role (user_id, role_id),
    key idx_role_id (role_id)
) engine = InnoDB default charset = utf8mb4 comment '用户角色关系表';
```

- `(user_id, role_id)` 联合唯一索引：防止同一个用户重复绑定同一个角色。实测重复插入 `(1, 1)` 报 `ERROR 1062: Duplicate entry '1-1' for key ... uk_user_role`。
- 这个联合索引也能加速「查某个用户的角色」；「查某个角色下的用户」靠 `idx_role_id`。

### 5.3 一对一：拆表，关联字段加唯一约束

用户的基本信息经常查，详细信息很少查，而且有大字段。拆成两张表，让常用的表更小、查得更快：

```sql
create table t_user_profile (
    id        bigint       primary key auto_increment comment '主键',
    user_id   bigint       not null comment '用户ID',
    real_name varchar(32)  comment '真实姓名',
    id_card   char(18)     comment '身份证号',
    address   varchar(255) comment '地址',
    intro     text         comment '个人简介',
    unique key uk_user_id (user_id)
) engine = InnoDB default charset = utf8mb4 comment '用户详情表';
```

`user_id` 上的**唯一**约束保证了「一对一」：一个用户只能有一条详情。

以上 6 张表的建表语句都实际执行过。

## 6. 业务表规范

### 6.1 三个必备字段

```sql
id          bigint   primary key auto_increment comment '主键',
create_time datetime not null default current_timestamp comment '创建时间',
update_time datetime not null default current_timestamp on update current_timestamp comment '更新时间',
```

`create_time`、`update_time` 交给数据库自动维护，代码里不用管。实测：

```sql
insert into tmp_ch04_order (order_no) values ('NO001');
-- create_time = 2026-11-20 20:44:14, update_time = 2026-11-20 20:44:14

-- 3 秒后
update tmp_ch04_order set status = 1 where id = 1;
-- create_time = 2026-11-20 20:44:14, update_time = 2026-11-20 20:44:17   ← 自动更新了

-- 6 秒后，再执行一次同样的 update（status 已经是 1）
update tmp_ch04_order set status = 1 where id = 1;
-- Rows matched: 1  Changed: 0
-- update_time 还是 20:44:17   ← 值没变化，不算修改，不更新时间
```

注意：时间是数据库服务器的时区。应用服务器、数据库、JDBC 连接串（`serverTimezone=Asia/Shanghai`）的时区要统一，否则会差 8 小时。

### 6.2 逻辑删除

重要数据不真的 `delete`，而是标记一下：

```sql
is_deleted tinyint not null default 0 comment '逻辑删除：0 未删除，1 已删除'
```

- 删除：`update ... set is_deleted = 1`
- 所有查询都要带 `where is_deleted = 0`（MyBatis-Plus 的 `@TableLogic` 会自动加）
- 好处：误删能恢复、留有历史记录、关联数据不会「断掉」。

### 6.3 逻辑删除和唯一索引的冲突 ⚠️

用户名有唯一索引。用户注销（逻辑删除）后，同一个用户名想重新注册：

```sql
-- uk_username (username)
insert into tmp_ch04_account (username) values ('zhangsan');
update tmp_ch04_account set is_deleted = 1 where username = 'zhangsan';
insert into tmp_ch04_account (username) values ('zhangsan');
-- ERROR 1062: Duplicate entry 'zhangsan' for key 'tmp_ch04_account.uk_username'
```

数据还在表里，唯一索引还管着它。

**方案 1：把 `is_deleted` 加进唯一索引** ❌

```sql
-- uk_username (username, is_deleted)
-- 第 1 次注册 → 删除 → 第 2 次注册：成功
-- 再删除第 2 个：
update tmp_ch04_account set is_deleted = 1 where username = 'zhangsan' and is_deleted = 0;
-- ERROR 1062: Duplicate entry 'zhangsan-1' for key 'tmp_ch04_account.uk_username'
```

只能删一次，第二次删除时 `('zhangsan', 1)` 就重复了。

**方案 2：删除时把标记设成自己的 id** ✅

```sql
create table tmp_ch04_account (
    id         bigint primary key auto_increment,
    username   varchar(20) not null,
    deleted_id bigint not null default 0 comment '0 未删除，删除时设为 id',
    unique key uk_username (username, deleted_id)
);
-- 注册 → 删除 → 注册 → 删除 → 注册，每次删除执行：
update tmp_ch04_account set deleted_id = id where username = 'zhangsan' and deleted_id = 0;
```
```
+----+----------+------------+
| id | username | deleted_id |
+----+----------+------------+
|  3 | zhangsan |          0 |   <- 当前有效的
|  1 | zhangsan |          1 |   <- 已删除
|  2 | zhangsan |          2 |   <- 已删除
+----+----------+------------+
```

已删除的记录 `deleted_id` 各不相同，不会冲突；未删除的 `deleted_id` 都是 0，唯一索引照样生效（实测再插入一个 `zhangsan` 报 `Duplicate entry 'zhangsan-0'`）。

另一个思路：删除时把数据移到一张历史表，原表真删除。

### 6.4 命名规范

| 对象 | 规范 | 例子 |
|---|---|---|
| 表名、字段名 | 小写字母 + 下划线，不用复数 | `t_order_item`、`create_time` |
| 布尔含义的字段 | `is_xxx`，类型 `tinyint` | `is_deleted` |
| 主键索引 | 固定是 `PRIMARY` | |
| 唯一索引 | `uk_字段名` | `uk_order_no` |
| 普通索引 | `idx_字段名` | `idx_user_id` |
| 表前缀 | 按业务模块或统一前缀 | `t_`、`sys_`、`order_` |

- 不用 MySQL 关键字做名字（`order`、`desc`、`status` 等能用但容易出问题，`order` 必须加反引号）。
- 表和每个字段**都写 `comment`**，状态类字段把每个值的含义写进去。半年后你自己都记不住 `status = 3` 是什么。

## 7. 字段类型和长度怎么选

### 7.1 金额必须用 decimal

```sql
create table tmp_ch04_money (f float, d double, m decimal(10, 2));
insert into tmp_ch04_money values (0.1, 0.1, 0.1), (0.2, 0.2, 0.2);
select sum(f), sum(d), sum(m) from tmp_ch04_money;
```
```
+---------------------+---------------------+--------+
| sum(f)              | sum(d)              | sum(m) |
+---------------------+---------------------+--------+
| 0.30000000447034836 | 0.30000000000000004 |   0.30 |
+---------------------+---------------------+--------+
```

`float`、`double` 是二进制浮点数，0.1 存不精确。`select * from tmp_ch04_money where f = 0.1` 实测**查不出任何数据**。

金额用 `decimal(总位数, 小数位数)`，或者用 `bigint` 存「分」。Java 里对应 `BigDecimal`（不要用 `double`）。

### 7.2 整数

| 类型 | 字节 | 范围（有符号） | 适合 |
|---|---|---|---|
| `tinyint` | 1 | -128 ~ 127 | 状态、类型、布尔、年龄 |
| `int` | 4 | 约 ±21 亿 | 数量、一般计数 |
| `bigint` | 8 | 约 ±922 亿亿 | 主键、外键 id、金额（分） |

- `int(11)` 里的 11 只是显示宽度，**不影响能存多大的数**，MySQL 8 已经不推荐写了。
- 不会是负数的加 `unsigned`，范围翻倍。

### 7.3 字符串

| 类型 | 适合 |
|---|---|
| `char(n)` | 长度固定：手机号 `char(11)`、身份证 `char(18)`、MD5 `char(32)` |
| `varchar(n)` | 长度不固定：姓名、邮箱、标题 |
| `text` | 很长的内容：文章正文、备注。不能设默认值，尽量不放在常用查询的表里 |

**`varchar(n)` 的 n 是字符数，不是字节数**：

```sql
-- username varchar(20)，插入 20 个汉字：成功
select username, char_length(username) chars, length(username) bytes ...;
-- chars = 20, bytes = 60     （utf8mb4 下一个汉字 3 字节）
-- 插入 21 个汉字：ERROR 1406: Data too long for column 'username'
```

长度按业务的真实上限定，留一点余量，不要无脑 `varchar(255)`：长度会影响排序、临时表时的内存占用，也起不到约束作用。

### 7.4 时间

| 类型 | 范围 | 说明 |
|---|---|---|
| `datetime` | 1000 ~ 9999 年 | **推荐**，存什么就是什么 |
| `timestamp` | 1970 ~ **2038** 年 | 会按连接时区转换；2038 年后溢出 |
| `date` | 只有日期 | 生日 |

不要用字符串存时间，没法比较大小、没法用日期函数，还占空间。

### 7.5 字符集

统一 `utf8mb4`。MySQL 的 `utf8`（`utf8mb3`）一个字符最多 3 字节，存不了 emoji 和部分生僻字。

## 8. alter table：修改表结构

### 8.1 常用语法

```sql
alter table t_user add column email varchar(100) not null default '' comment '邮箱';   -- 加字段
alter table t_user modify column username varchar(50) not null comment '用户名';       -- 改类型/长度
alter table t_user change column username user_name varchar(50) not null;            -- 改名 + 改类型
alter table t_user rename column user_name to username;                               -- 只改名
alter table t_user drop column email;                                                 -- 删字段
alter table t_user add index idx_age (age);                                           -- 加索引
alter table t_user rename to t_member;                                                -- 改表名
```

### 8.2 不同的修改，代价差别很大

MySQL 8 的 `alter table` 有三种执行方式：

| 方式 | 做法 | 代价 |
|---|---|---|
| `instant` | 只改表的元数据 | 瞬间完成 |
| `inplace` | 在原表上改，期间可以读写（Online DDL） | 要扫描或重建数据，但不阻塞业务 |
| `copy` | 新建一张表，把数据全部复制过去 | 大表要很久，**期间不能写** |

可以在语句后面写上期望的方式，做不到就直接报错，而不是悄悄用 `copy` 锁表。实测：

```sql
alter table tmp_ch04_user add column email varchar(100) not null default '', algorithm=instant;
-- Query OK（instant：加字段瞬间完成）

alter table tmp_ch04_user modify username varchar(50) not null, algorithm=inplace, lock=none;
-- Query OK（20 → 50 个字符，可以 inplace）

alter table tmp_ch04_user modify username varchar(100) not null, algorithm=inplace, lock=none;
-- ERROR 1846: ALGORITHM=INPLACE is not supported. Reason: Cannot change column type INPLACE. Try ALGORITHM=COPY.

alter table tmp_ch04_user add index idx_age (age), algorithm=inplace, lock=none;
-- Query OK（加索引可以 inplace，不阻塞读写）

alter table tmp_ch04_user modify age int, algorithm=inplace, lock=none;
-- ERROR 1845: ALGORITHM=INPLACE is not supported for this operation. Try ALGORITHM=COPY.（改类型要 copy）
```

`varchar` 扩长为什么有的行有的不行：`varchar` 用 1 个字节记录长度时最多表示 255 字节，utf8mb4 下 50 个字符 = 200 字节，还在 1 字节范围内；100 个字符 = 400 字节，长度前缀要变成 2 字节，必须重建表。

### 8.3 缩短长度可能失败或丢数据

```sql
alter table tmp_ch04_user modify username varchar(2) not null;
-- ERROR 1265: Data truncated for column 'username' at row 4
```

严格模式下，已有数据放不下就会报错。关闭严格模式时会直接截断数据。**改小长度、改类型之前，先查一下现有数据的最大长度。**

### 8.4 线上改表注意事项

1. 先确认会用 `instant`、`inplace` 还是 `copy`：在测试环境加上 `algorithm=...` 试一下。
2. 改表前检查长事务，并设置 `lock_wait_timeout`，避免元数据锁把整张表堵住（见[第 9 章 3.2](09-lock.md)）。
3. 大表改结构放在业务低峰期；必须 `copy` 的，用 `pt-online-schema-change`、`gh-ost` 这类工具。
4. 新加的字段带上 `default`，老代码不传这个字段也能正常插入。
5. 改表语句和代码一起纳入版本管理（Flyway、Liquibase，或者至少放进项目的 SQL 目录）。

## 9. 小结

1. 能加约束就加：`not null` + `default`、唯一的字段加唯一索引。约束是并发场景下唯一可靠的防重手段，代码里捕获 `1062`。
2. 生产环境开启严格模式，否则超长数据会被静默截断。
3. 互联网业务一般不用外键和级联，关联关系在代码里保证，但关联字段要建索引。
4. 每张表都有主键：单库用 `bigint` 自增，分库分表用雪花 ID，不用 UUID 做主键。自增 id 会不连续，不要赋予业务含义。
5. 先按三范式拆表，再有意识地冗余（快照、统计字段）。
6. 一对多在「多」的一方加关联字段；多对多建中间表并加联合唯一索引；一对一拆表并给关联字段加唯一约束。
7. 每张表都有 `id`、`create_time`、`update_time`，所有表和字段写 `comment`。
8. 逻辑删除和唯一索引一起用时，删除标记用 `deleted_id = id` 的方式。
9. 金额用 `decimal`，字符串长度按真实需求定，时间用 `datetime`，字符集用 `utf8mb4`。
10. 改表前确认执行方式、检查长事务，大表在低峰期改。

---

上一章：[多表查询 🟢](03-multi-table-query.md) · [目录](../README.md) · 下一章：[事务 🟢](05-transaction.md)

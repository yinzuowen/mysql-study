# 第 9 章 锁 🟡

> 锁用来协调多个事务**同时访问同一份数据**。写业务时你很少手动加锁，但下面这些问题都和锁有关：
> 接口偶尔卡住几十秒然后报 `Lock wait timeout exceeded`、日志里出现 `Deadlock found`、线上执行 `alter table` 之后整张表都查不动了、高并发扣库存出现超卖。
>
> 本章的实验都在本机 MySQL（InnoDB，默认隔离级别 Repeatable Read）的 `itcast.t_user` 上实际跑过。`t_user` 有主键 `id`（1–24）、普通索引 `idx_user_name(name)`，`age` 列上没有单独的索引。

## 1. 锁的分类

按锁住的范围，从大到小：

| 类别 | 锁住什么 | 典型场景 |
|---|---|---|
| 全局锁 | 整个数据库实例 | 全库逻辑备份 |
| 表级锁 | 整张表 | `lock tables`、改表结构（元数据锁）、意向锁 |
| 行级锁 | 索引上的记录或间隙 | InnoDB 的 `update`、`delete`、`select ... for update` |

按读写分：

- **共享锁（S，读锁）**：大家都能读，但都不能写。
- **排他锁（X，写锁）**：只有持有者能读写，别人既不能加读锁也不能加写锁。

|  | 已有 S 锁 | 已有 X 锁 |
|---|---|---|
| 再加 S 锁 | ✅ 兼容 | ❌ 等待 |
| 再加 X 锁 | ❌ 等待 | ❌ 等待 |

## 2. 全局锁

```sql
flush tables with read lock;   -- 加全局读锁：整个库只能读，不能写
-- 在这里做备份
unlock tables;                 -- 释放
```

加全局锁期间，所有写操作都会被阻塞，业务基本停摆。所以 InnoDB 的库备份**不用全局锁**，而是加 `--single-transaction`：

```bash
mysqldump --single-transaction -uroot -p itcast > itcast.sql
```

它在一个可重复读事务里导出数据，靠的是快照读（MVCC，见[第 11 章](11-internals-and-ops.md)），备份期间业务可以正常读写。

## 3. 表级锁

### 3.1 表锁

```sql
lock tables t_user read;    -- 表共享读锁：自己和别人都只能读
lock tables t_user write;   -- 表独占写锁：只有自己能读写，别人读写都要等
unlock tables;
```

InnoDB 有行锁，业务里**基本不用手动加表锁**，知道就行。

### 3.2 元数据锁（MDL）🟢 线上事故高发

元数据锁是**自动加的**，作用是：有事务在用这张表时，不让别人改表结构。

| 操作 | 加的 MDL | 和谁冲突 |
|---|---|---|
| `select` | `SHARED_READ` | 只和 `EXCLUSIVE` 冲突 |
| `insert`、`update`、`delete`、`select ... for update` | `SHARED_WRITE` | 只和 `EXCLUSIVE` 冲突 |
| `alter table` 等改表结构 | `EXCLUSIVE` | 和所有 MDL 冲突 |

**MDL 在事务提交之后才释放**，不是语句执行完就释放。这就带来一个经典事故：

| 时间 | 会话 A | 会话 B |
|---|---|---|
| 1 | `begin;`<br>`select count(*) from t_user;`<br>（事务一直没提交） | |
| 2 | | `alter table t_user add column tmp int;`<br>⏳ 等 A 的 `SHARED_READ` 释放 |
| 3 | | 之后所有对 `t_user` 的读写都排在 `alter` 后面，**整张表卡死** |

实测：会话 B 的状态是 `Waiting for table metadata lock`，在 `performance_schema.metadata_locks` 里能看到：

```
+-------------+-------------------+-------------+
| object_name | lock_type         | lock_status |
+-------------+-------------------+-------------+
| t_user      | SHARED_READ       | GRANTED     |   <- 会话 A 的未提交事务
| t_user      | SHARED_UPGRADABLE | GRANTED     |   <- alter 先拿到的
| t_user      | EXCLUSIVE         | PENDING     |   <- alter 在等这个
+-------------+-------------------+-------------+
```

怎么避免：

- 改表结构前，先看有没有长事务：`select * from information_schema.innodb_trx;`
- 改表时设置等待超时，等不到就放弃，别把整张表堵住：`set lock_wait_timeout = 5;`
- 大表改结构放在业务低峰期。

### 3.3 意向锁

问题：事务 A 锁住了 `t_user` 的某一行，这时事务 B 想给整张表加表锁，B 怎么知道表里有没有行被锁？一行一行去检查太慢。

解决：InnoDB 在加行锁之前，先在表上加一个**意向锁**，相当于在表门口挂个牌子「里面有行被锁了」。表锁只要看这个牌子就行。

| 意向锁 | 什么时候加 |
|---|---|
| 意向共享锁（IS） | 加行级 S 锁之前，如 `select ... for share` |
| 意向排他锁（IX） | 加行级 X 锁之前，如 `update`、`delete`、`select ... for update` |

意向锁之间互相兼容，只和表锁冲突，不会影响行锁之间的并发。下面实验结果里每次都有一行 `TABLE | IX`，就是它。

## 4. 行级锁 🟢

### 4.1 哪些语句会加行锁

| 语句 | 加的锁 |
|---|---|
| 普通 `select` | **不加锁**（快照读，读的是 MVCC 版本） |
| `select ... for share`（旧写法 `lock in share mode`） | S 锁 |
| `select ... for update` | X 锁 |
| `insert`、`update`、`delete` | X 锁（自动加） |

实测：普通 `select * from t_user where id = 10` 在事务里执行后，`performance_schema.data_locks` 里一行锁都没有。

### 4.2 三种行锁

| 锁 | 锁住什么 | `data_locks` 里的 `lock_mode` |
|---|---|---|
| 记录锁（Record Lock） | 索引上的一条记录 | `X,REC_NOT_GAP` |
| 间隙锁（Gap Lock） | 两条记录之间的空隙，不让别人往里插数据 | `X,GAP` |
| 临键锁（Next-Key Lock） | 记录 + 它前面的间隙 | `X` |

间隙锁和临键锁是为了在可重复读级别下**防止幻读**：把可能插入新数据的空隙也锁上。间隙锁之间不冲突，它只阻止插入。

### 4.3 行锁是加在索引上的

这是最重要的一条。用下面的语句查看当前事务加了哪些锁：

```sql
select object_name, index_name, lock_type, lock_mode, lock_data
from performance_schema.data_locks;
```

**情况 1：主键等值查询，记录存在 → 只锁这一行**

```sql
begin;
select * from t_user where id = 10 for update;
```
```
| t_user | NULL    | TABLE  | IX            | NULL |
| t_user | PRIMARY | RECORD | X,REC_NOT_GAP | 10   |   <- 只锁 id=10 这条记录
```

**情况 2：普通索引等值查询 → 锁记录，还锁前后的间隙**

```sql
begin;
update t_user set status = '9' where name = '白起';
```
```
| t_user | NULL          | TABLE  | IX            | NULL         |
| t_user | idx_user_name | RECORD | X,GAP         | '程咬金', 8  |   <- 下一条记录前的间隙
| t_user | idx_user_name | RECORD | X             | '白起', 10   |   <- 临键锁
| t_user | PRIMARY       | RECORD | X,REC_NOT_GAP | 10           |   <- 回表锁住主键记录
```

`name` 不是唯一索引，别的事务可能再插入一个「白起」，所以要把「白起」前后的间隙都锁上。同时主键索引上的那一行也会被锁。

**情况 3：主键等值查询，记录不存在 → 锁间隙**

```sql
begin;
select * from t_user where id = 30 for update;   -- 最大 id 是 24
```
```
| t_user | PRIMARY | RECORD | X | supremum pseudo-record |
```

`supremum` 表示「最后一条记录之后的间隙」。此时别的事务插入 `id = 25`、`id = 100` 都会被阻塞。

**情况 4：范围查询 → 锁范围内的记录和间隙**

```sql
begin;
select id from t_user where id between 10 and 12 for update;
```
```
| t_user | PRIMARY | RECORD | X,REC_NOT_GAP | 10 |
| t_user | PRIMARY | RECORD | X             | 11 |
| t_user | PRIMARY | RECORD | X             | 12 |
```

**情况 5：where 条件不走索引 → 锁住全表** ⚠️

```sql
begin;
update t_user set status = '9' where age = 27;   -- age 上没有单独的索引
```
```
| index_name | lock_mode | 锁的数量 |
| PRIMARY    | X         | 25       |   <- 24 行全部 + supremum
```

只想改 2 行（白起、韩信），却锁住了全部 24 行和所有间隙。这期间别的事务改任何一行、插入任何数据都要等。**写 `update`、`delete` 时，`where` 条件一定要能走索引**，执行前用 `explain` 看一下。

### 4.4 锁等待超时

拿不到锁时会等待，默认最多等 50 秒（`innodb_lock_wait_timeout`）：

| 时间 | 会话 A | 会话 B |
|---|---|---|
| 1 | `begin;`<br>`update t_user set status='9' where id=10;` | |
| 2 | | `update t_user set status='8' where id=10;`<br>⏳ 等待 |
| 3 | | `update t_user set ... where id=11;` ✅ 不同行，不受影响 |
| 4 | （一直不提交） | `ERROR 1205: Lock wait timeout exceeded` |

线上看到 `1205` 报错，基本就是有事务拿着锁太久：慢 SQL、事务里调了远程接口、或者事务忘了提交。

排查谁在等谁：

```sql
select * from sys.innodb_lock_waits;            -- 等待者、阻塞者、各自的 SQL
select * from information_schema.innodb_trx;    -- 当前所有事务，看 trx_started 找长事务
```

## 5. 死锁 🟢

两个事务**互相等对方手里的锁**：

| 时间 | 会话 A | 会话 B |
|---|---|---|
| 1 | `begin;`<br>`update t_user ... where id = 1;` 🔒 锁住 1 | |
| 2 | | `begin;`<br>`update t_user ... where id = 2;` 🔒 锁住 2 |
| 3 | `update t_user ... where id = 2;` ⏳ 等 B | |
| 4 | | `update t_user ... where id = 1;` ⏳ 等 A → 死锁 |
| 5 | ✅ 继续执行 | ❌ `ERROR 1213: Deadlock found when trying to get lock` |

InnoDB 会自动检测死锁（`innodb_deadlock_detect`，默认开启），回滚其中**代价小的那个**事务，另一个继续执行。

查看最近一次死锁：

```sql
show engine innodb status;   -- 看 LATEST DETECTED DEADLOCK 部分
```

实测输出（节选）：

```
*** (1) TRANSACTION:
update t_user set status=status where id=2
*** (1) HOLDS THE LOCK(S):        ... lock_mode X locks rec but not gap
*** (1) WAITING FOR THIS LOCK TO BE GRANTED:  ... waiting
*** (2) TRANSACTION:
update t_user set status=status where id=1
...
*** WE ROLL BACK TRANSACTION (2)
```

怎么减少死锁：

- **多个事务按相同的顺序加锁**。比如批量更新前，先把 id 排好序再逐个更新。
- 事务尽量小、尽量快，拿锁的时间越短越好。
- `where` 条件走索引，少锁行、少锁间隙。
- 代码里捕获死锁异常（`1213`），对整个事务**重试**一次。

## 6. 乐观锁与悲观锁 🟢 写业务时最常用

这两个是**思路**，不是 MySQL 里的某一种锁。典型场景：多人同时下单，扣减库存。

### 悲观锁：先锁住，再修改

认为一定会冲突，先用 `for update` 锁住这一行，别人只能等：

```sql
begin;
select stock from t_goods where id = 1 for update;   -- 锁住这件商品
-- 代码里判断 stock > 0
update t_goods set stock = stock - 1 where id = 1;
commit;
```

- 优点：逻辑直观，一定不会超卖。
- 缺点：并发高时大家排队等锁，吞吐量低。

### 乐观锁：不加锁，更新时检查有没有被改过

给表加一个 `version` 字段，更新时带上读到的版本号：

```sql
select stock, version from t_goods where id = 1;   -- 假设读到 version = 5

update t_goods
set stock = stock - 1, version = version + 1
where id = 1 and version = 5;
-- 影响行数 = 1：成功
-- 影响行数 = 0：被别人先改了，重新读取再试，或者直接提示失败
```

- 优点：不用等锁，读多写少时性能好。
- 缺点：冲突多时大量重试失败。

### 扣库存最简单的写法

很多时候不需要先查再改，直接把判断条件写进 `update`：

```sql
update t_goods set stock = stock - 1 where id = 1 and stock > 0;
-- 影响行数 = 0 说明库存不足
```

`update` 本身会加行锁，判断和扣减在一条语句里原子完成，不会超卖。

| | 悲观锁 | 乐观锁 |
|---|---|---|
| 做法 | `select ... for update` | `version` 字段 + 条件更新 |
| 适合 | 冲突多、必须成功（如转账） | 冲突少、读多写少（如编辑资料） |
| 冲突时 | 排队等待 | 更新失败，重试或报错 |

## 7. 小结

1. 普通 `select` 不加锁；`update`、`delete`、`for update` 加行锁。
2. 行锁加在索引上，**`where` 不走索引就会锁全表**。
3. 可重复读级别下有间隙锁，用来防止幻读，也是很多「明明没改同一行却被阻塞」的原因。
4. 事务里拿到的锁和 MDL **提交后才释放**，所以事务要小，不要在事务里做远程调用。
5. 改表结构前先查长事务，并设置 `lock_wait_timeout`。
6. 死锁会被自动检测并回滚一方，代码里要能重试；按相同顺序加锁能减少死锁。
7. 扣库存这类场景：优先用条件更新，其次乐观锁，冲突特别多时用悲观锁。

---

上一章：[SQL 优化 🟡](08-sql-optimization.md) · [目录](../README.md) · 下一章：[后端开发常见坑 🟢](10-backend-pitfalls.md)

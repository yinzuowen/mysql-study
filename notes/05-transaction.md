# 第 5 章 事务 🟢

> 事务保证「一组操作要么全部成功，要么全部失败」。写业务时下面这些情况都离不开它：
> 下单要同时扣库存、生成订单、扣余额，中间任何一步失败都要全部撤回；两个请求同时修改同一条数据，读到的值和预期不一样；Spring 里加了 `@Transactional` 却没有回滚；接口里的事务拖得太久，拖垮了整个库。
>
> 本章的实验都在本机 MySQL（InnoDB，默认隔离级别 Repeatable Read）上实际跑过，用的是临时建的账户表：
>
> ```sql
> create table tmp_ch05_account (id int primary key, name varchar(10), money decimal(10,2)) engine = InnoDB;
> insert into tmp_ch05_account values (1, '张三', 2000), (2, '李四', 2000);
> ```

## 1. 事务是什么

经典例子：张三给李四转账 1000 元，需要两条 SQL：

```sql
update tmp_ch05_account set money = money - 1000 where name = '张三';
update tmp_ch05_account set money = money + 1000 where name = '李四';
```

如果第一条执行成功，第二条执行前程序崩了，张三的钱扣了、李四没收到，1000 元就凭空消失了。**事务**把这两条 SQL 绑成一个整体：要么都生效，要么都不生效。

## 2. 怎么开启和结束事务

### 2.1 自动提交（autocommit）

MySQL 默认开启自动提交，**每条 SQL 自己就是一个事务**，执行完立即提交：

```sql
select @@autocommit;   -- 1：开启（默认）
```

所以平时单独执行一条 `update`，执行完就已经永久生效了。

### 2.2 显式事务

要把多条 SQL 放进一个事务，用 `begin`（或 `start transaction`）开始，`commit` 提交，`rollback` 回滚：

```sql
begin;
update tmp_ch05_account set money = money - 1000 where name = '张三';
update tmp_ch05_account set money = money + 1000 where name = '李四';
commit;
```

实测提交后：

```
| id | name | money   |
|  1 | 张三 | 1000.00 |
|  2 | 李四 | 3000.00 |
```

出错时回滚：

```sql
begin;
update tmp_ch05_account set money = money - 1000 where name = '张三';
-- 发现问题
rollback;   -- 张三的钱恢复原样，仍然是 1000.00
```

### 2.3 关闭自动提交

```sql
set autocommit = 0;   -- 只影响当前会话
update tmp_ch05_account set money = 0 where id = 2;
-- 没有 commit 就断开连接
```

实测：断开后重新查询，李四的钱仍然是 `2000.00`，修改**被自动回滚了**。关掉 autocommit 后，每条 SQL 都在等你手动 `commit`，忘了提交改动就丢了，还会一直拿着锁。**不要随便关 autocommit**，需要事务就显式 `begin`。

### 2.4 保存点（savepoint）

事务里可以设保存点，只回滚到某个位置，而不是全部回滚：

```sql
start transaction;
update tmp_ch05_account set money = money - 100 where id = 1;   -- 2000 → 1900
savepoint sp1;
update tmp_ch05_account set money = money - 500 where id = 1;   -- 1900 → 1400
rollback to savepoint sp1;                                     -- 撤销 -500，回到 1900
commit;
```

实测结果：张三的钱是 `1900.00`。用得不多，知道有这个功能就行。

## 3. ACID 四大特性

| 特性 | 含义 | InnoDB 怎么保证 |
|---|---|---|
| 原子性（Atomicity） | 事务里的操作要么全做，要么全不做 | **undo log**：记录修改前的数据，回滚时用它恢复 |
| 一致性（Consistency） | 事务前后数据都满足业务规则（转账前后总金额不变） | 由另外三个特性共同保证，加上约束和业务代码 |
| 隔离性（Isolation） | 并发执行的事务互不干扰 | **锁** + **MVCC**（多版本并发控制） |
| 持久性（Durability） | 提交后数据永久保存，宕机也不丢 | **redo log**：提交时先把修改写进日志文件，崩溃后用它恢复 |

undo log、redo log、MVCC 的原理见[第 11 章](11-internals-and-ops.md)，锁见[第 9 章](09-lock.md)。入门阶段记住这张表就够了。

## 4. 并发事务的三个问题

多个事务同时操作同一份数据时，可能出现下面三种问题：

| 问题 | 现象 |
|---|---|
| 脏读 | 读到了别的事务**还没提交**的数据 |
| 不可重复读 | 同一事务里两次读同一行，结果不一样（中间被别人改了并提交） |
| 幻读 | 同一事务里按同样的条件查询，前后行数不一样（中间被别人插入了数据） |

下面在本机上逐个复现。

### 4.1 脏读（Read Uncommitted 下出现）

| 时间 | 会话 A | 会话 B（Read Uncommitted） |
|---|---|---|
| 1 | `begin;`<br>`update tmp_ch05_account set money = money - 1000 where id = 1;`<br>（还没提交） | |
| 2 | | `set session transaction isolation level read uncommitted;`<br>`begin;`<br>`select * from tmp_ch05_account where id = 1;`<br>👉 读到 `1000.00` |
| 3 | `rollback;` | |
| 4 | | 实际数据仍然是 `2000.00`，B 刚才读到的 1000 是**从来没存在过的数据** |

把会话 B 的隔离级别换成 `read committed` 重做一遍，第 2 步读到的就是 `2000.00`，脏读消失。

### 4.2 不可重复读（Read Committed 下出现）

| 时间 | 会话 A | 会话 B（Read Committed） |
|---|---|---|
| 1 | | `begin;`<br>`select money from tmp_ch05_account where id = 1;`<br>👉 `2000.00` |
| 2 | `update tmp_ch05_account set money = money - 500 where id = 1;`<br>（自动提交） | |
| 3 | | `select money from tmp_ch05_account where id = 1;`<br>👉 `1500.00`，**同一事务里两次读到的不一样** |

把会话 B 换成 `repeatable read`（MySQL 默认）重做：A 再扣 500 后，B 第二次读到的仍然是第一次的值 `1500.00`，不可重复读消失。

可重复读是靠 MVCC 实现的：事务里**第一次**普通 `select` 时生成一个快照，之后的普通 `select` 都读这个快照。

### 4.3 幻读（Repeatable Read 下的特殊情况）

| 时间 | 会话 A | 会话 B（Repeatable Read） |
|---|---|---|
| 1 | | `begin;`<br>`select id, name from tmp_ch05_account;`<br>👉 2 行：张三、李四 |
| 2 | `insert into tmp_ch05_account values (3, '王五', 2000);`<br>（自动提交） | |
| 3 | | `select id, name from tmp_ch05_account;`<br>👉 仍然是 2 行（快照读，看不到新插入的行） |
| 4 | | `select id, name from tmp_ch05_account for update;`<br>👉 **3 行**，多了王五 |
| 5 | | `insert into tmp_ch05_account values (3, '王五', 0);`<br>👉 `ERROR 1062: Duplicate entry '3' for key 'tmp_ch05_account.PRIMARY'` |

第 3 步明明查不到 id = 3，第 5 步插入时却提示 id = 3 已经存在，就像见了「幽灵」，这就是幻读。

原因是 MySQL 有两种读：

| | 快照读 | 当前读 |
|---|---|---|
| 语句 | 普通 `select` | `select ... for update`、`select ... for share`、`insert`、`update`、`delete` |
| 读的是 | 事务开始时的快照（MVCC） | 数据库里**最新**的已提交数据，并加锁 |

`update` 也是当前读。再做一次实验：会话 B 开事务后先查到 2 行，A 插入王五，B 执行 `update tmp_ch05_account set money = money + 1 where id = 3;`，实测**影响 1 行**；之后 B 再普通 `select`，王五出现了（`2001.00`），因为是自己改过的行。

**怎么彻底避免**：如果会话 B 一开始就用当前读 `select ... where id >= 1 for update`，InnoDB 会加上间隙锁（见[第 9 章](09-lock.md)），A 的 `insert` 会被阻塞。实测 A 等到超时：`ERROR 1205: Lock wait timeout exceeded`。

所以说 MySQL 的可重复读「**大部分**解决了幻读」：只用快照读或只用当前读都不会有问题，**同一事务里先快照读、再当前读**才会出现上面的现象。

## 5. 隔离级别

| 隔离级别 | 脏读 | 不可重复读 | 幻读 | 说明 |
|---|---|---|---|---|
| Read Uncommitted | ✗ 会出现 | ✗ 会出现 | ✗ 会出现 | 基本不用 |
| Read Committed | ✓ 解决 | ✗ 会出现 | ✗ 会出现 | Oracle、PostgreSQL 的默认级别，部分互联网公司也会把 MySQL 改成它 |
| **Repeatable Read** | ✓ 解决 | ✓ 解决 | 大部分解决 | **MySQL 默认** |
| Serializable | ✓ 解决 | ✓ 解决 | ✓ 解决 | 读也加锁，并发性能最差 |

隔离级别越高，数据越安全，并发性能越差。**一般用默认的就行**。

查看和设置：

```sql
select @@transaction_isolation, @@global.transaction_isolation;

set session transaction isolation level read committed;   -- 只影响当前连接
set global  transaction isolation level read committed;   -- 影响之后新建的连接，需要权限，慎用
```

实测 `set session` 后：

```
| @@transaction_isolation | @@global.transaction_isolation |
| READ-COMMITTED          | REPEATABLE-READ                |
```

当前会话变了，全局没变。

## 6. 会隐式提交的语句

有些语句执行时会**自动先提交**当前事务，之后再 `rollback` 也没用了。最常见的是 DDL：

```sql
begin;
update tmp_ch05_account set money = 0 where id = 1;
create table tmp_ch05_x (id int);   -- DDL：先把上面的 update 提交了
rollback;                           -- 什么也回滚不了
select * from tmp_ch05_account where id = 1;
```

实测：张三的钱变成了 `0.00`，`rollback` 没有生效。

会隐式提交的语句包括：

- DDL：`create`、`alter`、`drop`、`truncate`、`rename table`
- 用户和权限：`create user`、`grant`、`revoke`
- 锁表：`lock tables`、`unlock tables`
- 在事务里再执行一次 `begin` / `start transaction`

所以**不要把改表结构和改数据放在同一个事务里**，数据库迁移脚本要特别注意。

## 7. 长事务 ⚠️

长事务指开启后很久不提交的事务。危害：

- 一直拿着行锁，别的事务要改这些行只能等，最后报 `Lock wait timeout exceeded`。
- 一直拿着元数据锁，改表结构会把整张表卡死（见[第 9 章](09-lock.md)）。
- MVCC 需要为它保留旧版本数据，undo log 越积越多，占空间、拖慢查询。
- 一直占着一个数据库连接，连接池容易被耗尽。

查看当前所有事务，按开始时间找最久的：

```sql
select trx_id, trx_state, trx_started,
       timestampdiff(second, trx_started, now()) seconds,
       trx_rows_locked, trx_mysql_thread_id thread_id, trx_query
from information_schema.innodb_trx
order by trx_started;
```

实测（另一个会话执行了 `update` 后在 `sleep`）：

```
| trx_state | trx_started         | seconds | trx_rows_locked | thread_id | trx_query       |
| RUNNING   | 2026-11-20 20:42:43 |       2 |               1 | 194       | select sleep(3) |
```

`trx_query` 显示的是**当前正在执行**的语句，事务空闲时是 `NULL`。确认是异常的长事务后，可以用 `kill <thread_id>;` 断开它，事务会自动回滚。

## 8. 在 Spring 里使用事务

后端代码里一般不手写 `begin`/`commit`，而是用 Spring 的 `@Transactional`：

```java
@Service
public class AccountService {

    @Transactional(rollbackFor = Exception.class)
    public void transfer(Long fromId, Long toId, BigDecimal amount) {
        accountMapper.decrease(fromId, amount);
        accountMapper.increase(toId, amount);
    }
}
```

方法正常返回就提交，抛出异常就回滚。

### 8.1 常见的失效场景

| 场景 | 为什么失效 | 正确做法 |
|---|---|---|
| 同一个类里，方法 A 调用带 `@Transactional` 的方法 B | 事务靠代理实现，`this.b()` 没经过代理 | 把 B 放到另一个 Bean 里，或注入自身代理再调用 |
| 方法不是 `public` | Spring 默认只代理 `public` 方法 | 改成 `public` |
| 异常被自己 `catch` 了没抛出 | Spring 看不到异常，以为成功了，照常提交 | 处理完重新抛出，或手动 `TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()` |
| 抛出的是受检异常（如 `IOException`） | 默认**只回滚 `RuntimeException` 和 `Error`** | 写 `@Transactional(rollbackFor = Exception.class)` |
| 类没有被 Spring 管理（自己 `new` 的对象） | 没有代理 | 用注入的 Bean |
| 数据库表是 MyISAM | 引擎不支持事务 | 用 InnoDB |

### 8.2 传播行为

一个事务方法调用另一个事务方法时，第二个方法怎么处理事务：

| 传播行为 | 含义 | 场景 |
|---|---|---|
| `REQUIRED`（默认） | 有事务就加入，没有就新建 | 绝大多数情况 |
| `REQUIRES_NEW` | 不管有没有，都新建一个独立事务，外层事务先挂起 | 记录操作日志：主业务失败回滚了，日志仍要保存 |

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void saveLog(String content) { ... }
```

注意：`REQUIRED` 下内层方法抛异常，即使外层 `catch` 住了，整个事务也已经被标记为只能回滚，提交时会报 `Transaction rolled back because it has been marked as rollback-only`。

### 8.3 事务里不要做的事

- **调用远程接口**（HTTP、RPC）：网络慢或超时，事务就一直拿着锁和连接。
- **发消息、发短信、发邮件**：事务回滚了，消息却已经发出去了。应该在事务提交后再发（如 `@TransactionalEventListener`）。
- **耗时的计算、读写文件**：放在事务外面先做完。
- **一次处理大量数据**：拆成多个小批次，每批一个事务。
- **用户交互**：不能开着事务等用户操作。

原则：**事务里只放必须一起成功或失败的数据库操作**，越短越好。

## 9. 小结

1. MySQL 默认自动提交，每条 SQL 是一个事务；多条 SQL 要一起成功就用 `begin` … `commit` / `rollback`。
2. ACID：原子性靠 undo log，持久性靠 redo log，隔离性靠锁和 MVCC，一致性是最终目标。
3. 三个并发问题：脏读、不可重复读、幻读；MySQL 默认的可重复读解决了前两个，幻读只在「先快照读、再当前读」时出现。
4. 普通 `select` 是快照读，`for update` / `update` / `delete` / `insert` 是当前读。
5. DDL 会隐式提交事务，改表结构和改数据不要放在一个事务里。
6. 长事务危害大，用 `information_schema.innodb_trx` 查找。
7. `@Transactional` 记住三个坑：同类自调用、异常被吞、受检异常默认不回滚（加 `rollbackFor = Exception.class`）。
8. 事务里不调远程接口、不发消息，越短越好。

---

上一章：[约束与表设计 🟢](04-table-design.md) · [目录](../README.md) · 下一章：[存储引擎 🟡](06-storage-engine.md)

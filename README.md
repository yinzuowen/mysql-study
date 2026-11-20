# MySQL 入门整理（后端开发视角）

> 写给刚入门的后端开发：先会用、用对，再理解原理。
> 标记说明：🟢 必须掌握（写业务每天都用） · 🟡 进阶（面试常问、排查问题要用） · ⚪ 了解即可（知道有这回事，用到再查）

## 仓库结构

```
mysql-study/
├── README.md     目录（本文件）
├── notes/        知识点整理，按章节，每章一个 md
├── practice/     跟着课程写的练习：查询语句和性能分析笔记
└── data/         建表语句和测试数据
```

## 目录

| 章节 | 内容 | 优先级 |
|---|---|---|
| [第 1 章 基础概念](notes/01-basics.md) | SQL 分类、数据类型怎么选、增删改查 | 🟢 |
| [第 2 章 单表查询](notes/02-single-table-query.md) | 执行顺序、聚合分组、分页 | 🟢 |
| [第 3 章 多表查询](notes/03-multi-table-query.md) | 内连接、左连接、子查询、`union all` | 🟢 |
| [第 4 章 约束与表设计](notes/04-table-design.md) | 约束、业务表写法、表之间的关系 | 🟢 |
| [第 5 章 事务](notes/05-transaction.md) | ACID、并发问题、隔离级别 | 🟢 |
| [第 6 章 存储引擎](notes/06-storage-engine.md) | InnoDB 和 MyISAM | 🟡 |
| [第 7 章 索引](notes/07-index.md) | B+ 树、回表、覆盖索引、索引失效 | 🟢 / 🟡 |
| [第 8 章 SQL 优化](notes/08-sql-optimization.md) | 批量插入、排序分组、深分页、count | 🟡 |
| [第 9 章 锁](notes/09-lock.md) | 全局锁、表锁、行锁、死锁 | 🟡 |
| [第 10 章 后端开发常见坑](notes/10-backend-pitfalls.md) | SQL 注入、N+1、大事务、时区 | 🟢 |
| [第 11 章 原理与运维](notes/11-internals-and-ops.md) | MVCC、日志、主从复制、分库分表 | ⚪ / 🟡 |

性能分析与索引使用的详细示例（`explain` 实测结果）见 [04-performance.md](practice/04-performance.md)。

## 下一步

1. 把 [schema.sql](data/schema.sql) 和 [t_user.sql](data/t_user.sql) 导入数据库，自己把 [01](practice/01-subquery.sql)、[02](practice/02-join-practice.sql) 里的查询改写一遍。
2. 在 `t_user` 上建、删索引，用 `explain` 对比效果，对照 [04-performance.md](practice/04-performance.md) 里的结论。
3. 开两个终端窗口，各开一个事务，亲手复现一次脏读、不可重复读。
4. 在自己的后端项目里，找一条列表查询，用 `explain` 看它有没有走索引。

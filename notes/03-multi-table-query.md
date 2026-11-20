# 第 3 章 多表查询 🟢

> 本章练习：[01-subquery.sql](../practice/01-subquery.sql)、[02-join-practice.sql](../practice/02-join-practice.sql)

> 为什么要学：业务数据几乎不会放在一张表里。订单列表要显示用户名，员工列表要显示部门名，学生详情要列出选了哪些课，这些都要多表查询。
> 写业务时常见的问题：列表数据莫名其妙变多（重复行）、统计数字翻倍、该显示的记录不见了、`not in` 查出来是空的。本章把这些坑都实际跑一遍。
>
> 本章示例都在本机 `itcast` 库上实际跑过，用到的表和数据如下。

## 0. 示例数据

**部门 `t_dept`**（6 行，其中测试部没有员工）：

| id | name |
|---|---|
| 1 | 研发部 |
| 2 | 市场部 |
| 3 | 财务部 |
| 4 | 销售部 |
| 5 | 总经办 |
| 7 | 测试部 |

**员工 `t_emp`**（7 行，其中熊杨没有部门，`manager_id` 是直属领导的 `id`）：

| id | name | birth | city | dept_id | manager_id | salary |
|---|---|---|---|---|---|---|
| 1 | 高雄 | 1990-01-01 | 北京 | 1 | NULL | 25000 |
| 2 | 汪瑜 | 1991-02-02 | 武汉 | 2 | 1 | 20000 |
| 3 | 卢科 | 1988-07-01 | 武汉 | 3 | 1 | 20000 |
| 4 | 吴利平 | 1999-03-03 | 武汉 | 4 | 2 | 15000 |
| 5 | 侯明星 | NULL | 上海 | 5 | 3 | 12000 |
| 6 | 熊杨 | 1990-05-05 | 武汉 | NULL | NULL | 8000 |
| 7 | 王小焕 | 1989-04-04 | 北京 | 1 | 4 | 4500 |

**工资等级 `t_salary_grade`**：`grade`、`low`、`high` 三列，1 级 0–3000，2 级 3001–5000，……，8 级 25001–30000。

**学生、课程、选课**（多对多）：学生 `t_student`（高启强、陈书婷、小虎），课程 `t_course`（Java、Php、C++），中间表 `t_student_course(student_id, course_id)` 记录谁选了哪门课。

## 1. 笛卡尔积：多表查询的起点

```sql
select count(*) from t_emp, t_dept;
```
```
+----------+
| count(*) |
+----------+
|       42 |
+----------+
```

7 个员工 × 6 个部门 = 42 行，每个员工和每个部门都配了一次对，这就是**笛卡尔积**。其中绝大部分组合没有意义。

多表查询的本质就是：**先做笛卡尔积，再用连接条件把有意义的组合挑出来**。（MySQL 实际执行时不会真的先生成 42 行，但结果等价。）

> ⚠️ 连接条件漏写，结果就是笛卡尔积。两张 1 万行的表就是 1 亿行，接口直接超时。**有 n 张表，至少要有 n - 1 个连接条件。**

## 2. 连接查询

### 2.1 内连接：两边都匹配上的行

两种写法，结果一样：

```sql
-- 隐式内连接：表之间用逗号，条件写在 where 里
select e.name, d.name dept from t_emp e, t_dept d where e.dept_id = d.id;

-- 显式内连接（推荐）：join ... on，连接条件和过滤条件分开写，不容易漏
select e.name, d.name dept from t_emp e join t_dept d on e.dept_id = d.id;
```
```
+-----------+-----------+
| name      | dept      |
+-----------+-----------+
| 高雄      | 研发部    |
| 王小焕    | 研发部    |
| 汪瑜      | 市场部    |
| 卢科      | 财务部    |
| 吴利平    | 销售部    |
| 侯明星    | 总经办    |
+-----------+-----------+
```

只有 6 行：**没有部门的熊杨不见了**，没有员工的测试部也不在。内连接只保留两边都能匹配上的行。

`join` 和 `inner join` 是一回事，`inner` 可以省略。

### 2.2 左外连接：左表全部保留

```sql
select e.name, d.name dept from t_emp e left join t_dept d on e.dept_id = d.id;
```
```
+-----------+-----------+
| name      | dept      |
+-----------+-----------+
| 高雄      | 研发部    |
| 汪瑜      | 市场部    |
| 卢科      | 财务部    |
| 吴利平    | 销售部    |
| 侯明星    | 总经办    |
| 熊杨      | NULL      |
| 王小焕    | 研发部    |
+-----------+-----------+
```

左表 `t_emp` 的 7 行都在，熊杨匹配不到部门，右表的列填 `NULL`。

**写业务时怎么选**：主表的数据**必须完整显示**时用 `left join`。比如「员工列表」，不能因为某个员工还没分配部门就不显示他。

### 2.3 右外连接

```sql
select d.name dept, e.name from t_emp e right join t_dept d on e.dept_id = d.id;
```
```
+-----------+-----------+
| dept      | name      |
+-----------+-----------+
| 研发部    | 高雄      |
| 研发部    | 王小焕    |
| 市场部    | 汪瑜      |
| 财务部    | 卢科      |
| 销售部    | 吴利平    |
| 总经办    | 侯明星    |
| 测试部    | NULL      |
+-----------+-----------+
```

右表 `t_dept` 全部保留。`a right join b` 等价于 `b left join a`，**实际工作中统一写 `left join`**，把要完整保留的表放左边，读起来更清楚。

### 2.4 全外连接：MySQL 不支持，用 union 模拟

MySQL 没有 `full join`。要两边都完整保留，就把左连接和右连接的结果用 `union` 合起来：

```sql
select e.name, d.name dept from t_emp e left join t_dept d on e.dept_id = d.id
union
select e.name, d.name from t_emp e right join t_dept d on e.dept_id = d.id;
```
```
+-----------+-----------+
| name      | dept      |
+-----------+-----------+
| 高雄      | 研发部    |
| 汪瑜      | 市场部    |
| 卢科      | 财务部    |
| 吴利平    | 销售部    |
| 侯明星    | 总经办    |
| 熊杨      | NULL      |
| 王小焕    | 研发部    |
| NULL      | 测试部    |
+-----------+-----------+
```

没有部门的熊杨、没有员工的测试部都在。这里必须用 `union`（去重），用 `union all` 的话两边都匹配上的 6 行会出现两次。

### 2.5 找「没有匹配」的数据：left join + is null

```sql
-- 没有部门的员工
select e.name from t_emp e left join t_dept d on e.dept_id = d.id where d.id is null;
-- 熊杨

-- 没有员工的部门
select d.name from t_dept d left join t_emp e on e.dept_id = d.id where e.id is null;
-- 测试部
```

这是非常常用的套路：「没下过单的用户」「没有商品的分类」都这么查。

### 2.6 自连接：同一张表连自己

员工和直属领导都在 `t_emp` 里。把同一张表起两个别名，当成两张表来连：

```sql
select e.name emp, m.name manager
from t_emp e
left join t_emp m on e.manager_id = m.id;
```
```
+-----------+-----------+
| emp       | manager   |
+-----------+-----------+
| 高雄      | NULL      |
| 汪瑜      | 高雄      |
| 卢科      | 高雄      |
| 吴利平    | 汪瑜      |
| 侯明星    | 卢科      |
| 熊杨      | NULL      |
| 王小焕    | 吴利平    |
+-----------+-----------+
```

- 自连接**必须起别名**，否则分不清哪个是员工、哪个是领导。
- 用 `left join` 是为了保留没有领导的高雄（老板）。用内连接的话，他就不见了。
- 类似场景：评论和回复、分类和父分类、地区和上级地区。

### 2.7 非等值连接：工资等级

连接条件不一定是 `=`，也可以是范围：

```sql
select e.name, e.salary, s.grade
from t_emp e
join t_salary_grade s on e.salary between s.low and s.high;
```
```
+-----------+--------+-------+
| name      | salary | grade |
+-----------+--------+-------+
| 王小焕    |   4500 |     2 |
| 熊杨      |   8000 |     3 |
| 侯明星    |  12000 |     5 |
| 吴利平    |  15000 |     5 |
| 卢科      |  20000 |     6 |
| 汪瑜      |  20000 |     6 |
| 高雄      |  25000 |     7 |
+-----------+--------+-------+
```

### 2.8 left join 的条件写在 on 里还是 where 里 ⚠️

需求：列出所有员工，只显示研发部的部门名。两种写法看起来差不多，结果完全不同：

```sql
-- 写法 A：条件放在 on 里
select e.name, d.name dept from t_emp e
left join t_dept d on e.dept_id = d.id and d.name = '研发部';
```
```
+-----------+-----------+
| name      | dept      |
+-----------+-----------+
| 高雄      | 研发部    |
| 汪瑜      | NULL      |
| 卢科      | NULL      |
| 吴利平    | NULL      |
| 侯明星    | NULL      |
| 熊杨      | NULL      |
| 王小焕    | 研发部    |
+-----------+-----------+
```

```sql
-- 写法 B：条件放在 where 里
select e.name, d.name dept from t_emp e
left join t_dept d on e.dept_id = d.id
where d.name = '研发部';
```
```
+-----------+-----------+
| name      | dept      |
+-----------+-----------+
| 高雄      | 研发部    |
| 王小焕    | 研发部    |
+-----------+-----------+
```

7 行 vs 2 行。原因：

- `on` 是**连接时**的条件：决定右表哪些行能配上。配不上的，左表的行照样保留，右表填 `NULL`。
- `where` 是**连接完之后**的过滤：右表为 `NULL` 的行，`d.name = '研发部'` 不成立，被过滤掉。效果等于变成了内连接。

规则：
- 对**右表**的过滤条件，想保留左表全部数据 → 写在 `on` 里。
- 对**左表**的过滤条件 → 写在 `where` 里（写在 `on` 里不会过滤左表）。
- 对内连接来说，条件写在 `on` 还是 `where` 结果一样。

## 3. 子查询

把一个查询的结果当成另一个查询的条件或数据来源。按子查询返回的结果形状分四种：

| 类型 | 返回 | 常用操作符 |
|---|---|---|
| 标量子查询 | 一个值（一行一列） | `=`、`>`、`<` 等 |
| 列子查询 | 一列多行 | `in`、`not in`、`any`、`all` |
| 行子查询 | 一行多列 | `=`、`<>`、`in` |
| 表子查询 | 多行多列 | `in`，或放在 `from` 后当临时表 |

### 3.1 标量子查询

```sql
-- 工资高于平均工资的员工（平均工资 14928.57）
select name, salary from t_emp where salary > (select avg(salary) from t_emp);
```
```
+-----------+--------+
| name      | salary |
+-----------+--------+
| 高雄      |  25000 |
| 汪瑜      |  20000 |
| 卢科      |  20000 |
| 吴利平    |  15000 |
+-----------+--------+
```

子查询必须**只返回一行**，否则报错 `Subquery returns more than 1 row`。

### 3.2 列子查询：in、any、all

```sql
-- 销售部或市场部的员工
select name from t_emp
where dept_id in (select id from t_dept where name in ('销售部', '市场部'));
-- 汪瑜、吴利平

-- 比财务部所有人工资都高（> all：比最大值还大）
select name, salary from t_emp
where salary > all (select salary from t_emp where dept_id = 3);
-- 高雄 25000（财务部只有卢科 20000）

-- 比研发部任意一人工资高（> any：比最小值大就行）
select name, salary from t_emp
where salary > any (select salary from t_emp where dept_id = 1);
-- 6 人，只有工资 4500 的王小焕本人不满足（研发部最低就是他的 4500）
```

| 写法 | 等价于 |
|---|---|
| `> all (子查询)` | `> (select max(...))` |
| `> any (子查询)`（`some` 同义） | `> (select min(...))` |
| `= any (子查询)` | `in (子查询)` |

### 3.3 not in 遇到 NULL：查出来是空的 ⚠️

需求：没有员工的部门。直觉写法：

```sql
select name from t_dept where id not in (select dept_id from t_emp);
```

**实测结果是空的，一行都没有。** 应该查出测试部才对。

原因：子查询结果里有熊杨的 `dept_id = NULL`。`id not in (1, 2, 3, 4, 5, NULL)` 相当于 `id <> 1 and ... and id <> NULL`，而任何值和 `NULL` 比较的结果都是「未知」，整个条件永远不成立。

解决：

```sql
-- 方法 1：子查询里排除 NULL
select name from t_dept where id not in (select dept_id from t_emp where dept_id is not null);

-- 方法 2：用 not exists（推荐，不受 NULL 影响）
select name from t_dept d where not exists (select 1 from t_emp e where e.dept_id = d.id);

-- 方法 3：left join + is null（见 2.5）
```

三种写法都查出「测试部」。

### 3.4 行子查询

```sql
-- 和卢科工资、直属领导都相同的员工
select name, salary, manager_id from t_emp
where (salary, manager_id) = (select salary, manager_id from t_emp where name = '卢科');
```
```
+--------+--------+------------+
| name   | salary | manager_id |
+--------+--------+------------+
| 汪瑜   |  20000 |          1 |
| 卢科   |  20000 |          1 |
+--------+--------+------------+
```

### 3.5 表子查询：放在 from 后面当临时表

```sql
-- 1990-01-01 之后出生的员工及其部门
select e.name, d.name dept
from (select * from t_emp where birth > '1990-01-01') e
left join t_dept d on e.dept_id = d.id;
```
```
+-----------+-----------+
| name      | dept      |
+-----------+-----------+
| 汪瑜      | 市场部    |
| 吴利平    | 销售部    |
| 熊杨      | NULL      |
+-----------+-----------+
```

`from` 后面的子查询（派生表）**必须起别名**。

### 3.6 exists

`exists (子查询)`：子查询**有没有返回行**，不关心返回什么，所以习惯写 `select 1`。

```sql
-- 有员工的部门
select d.name from t_dept d where exists (select 1 from t_emp e where e.dept_id = d.id);
-- 研发部、市场部、财务部、销售部、总经办
```

### 3.7 相关子查询

上面 `exists` 里的子查询用到了外层的 `d.id`，这种叫**相关子查询**：逻辑上外层每一行都要执行一次子查询。

```sql
-- 工资高于本部门平均工资的员工
select e.name, e.salary, e.dept_id from t_emp e
where e.salary > (select avg(e2.salary) from t_emp e2 where e2.dept_id = e.dept_id);
```
```
+--------+--------+---------+
| name   | salary | dept_id |
+--------+--------+---------+
| 高雄   |  25000 |       1 |
+--------+--------+---------+
```

研发部平均 (25000 + 4500) / 2 = 14750，只有高雄高于平均。其他部门都只有一个人，工资等于平均值，不算「高于」。

放在 `select` 里也很常见：

```sql
-- 每个部门的人数
select d.name, (select count(*) from t_emp e where e.dept_id = d.id) cnt from t_dept d;
```
```
+-----------+------+
| name      | cnt  |
+-----------+------+
| 研发部    |    2 |
| 市场部    |    1 |
| 财务部    |    1 |
| 销售部    |    1 |
| 总经办    |    1 |
| 测试部    |    0 |
+-----------+------+
```

### 3.8 in、exists、join 怎么选

网上常说「大表用 exists、小表用 in」，那是老版本的经验。MySQL 8 会把 `in` 和 `exists` 子查询都优化成**半连接（semi-join）**，实测两种写法的执行计划完全一样：

```sql
explain format=traditional select d.name from t_dept d where d.id in (select dept_id from t_emp);
explain format=traditional select d.name from t_dept d where exists (select 1 from t_emp e where e.dept_id = d.id);
```
```
| select_type | table | type | key            | Extra                      |
| SIMPLE      | d     | ALL  | NULL           | NULL                       |
| SIMPLE      | t_emp | ref  | fk_emp_dept_id | Using index; FirstMatch(d) |
```

实际建议：

- **只是判断「有没有」**（有员工的部门）：用 `in` 或 `exists`，哪个读着顺用哪个。`join` 在一对多时会产生重复行，还得 `distinct`。
- **判断「没有」**：用 `not exists` 或 `left join ... is null`，**避免 `not in`**（见 3.3）。
- **需要右表的列**（员工的部门名）：只能用 `join`。
- 写完用 `explain` 看一下，确认连接列上有索引。

## 4. union 和 union all

把多个查询的结果**上下拼接**。要求每个查询的列数相同，类型兼容。

```sql
select city from t_emp where dept_id = 1
union all
select city from t_emp where salary > 15000;
```
```
北京, 北京, 北京, 武汉, 武汉     -- 5 行，原样拼接
```

```sql
select city from t_emp where dept_id = 1
union
select city from t_emp where salary > 15000;
```
```
北京, 武汉                       -- 2 行，去重
```

| | union all | union |
|---|---|---|
| 去重 | 不去重 | 去重 |
| 性能 | 快 | 要额外排序或哈希去重，慢 |

**默认用 `union all`**，确实需要去重时再用 `union`。列转行（见 [03-row-column-transform.sql](../practice/03-row-column-transform.sql)）就是 `union all` 的典型用法。

## 5. 多对多查询

学生和课程是多对多：一个学生选多门课，一门课有多个学生。中间表 `t_student_course` 把它们连起来，查询时要连 3 张表：

```sql
select s.name, c.name course
from t_student s
join t_student_course sc on s.id = sc.student_id
join t_course c on sc.course_id = c.id
order by s.id, c.id;
```
```
+-----------+--------+
| name      | course |
+-----------+--------+
| 高启强    | Java   |
| 高启强    | Php    |
| 高启强    | C++    |
| 陈书婷    | Php    |
| 陈书婷    | C++    |
| 小虎      | C++    |
+-----------+--------+
```

每个学生一行、课程合并显示：

```sql
select s.name, count(*) cnt, group_concat(c.name order by c.id) courses
from t_student s
join t_student_course sc on s.id = sc.student_id
join t_course c on c.id = sc.course_id
group by s.id, s.name;
```
```
+-----------+-----+--------------+
| name      | cnt | courses      |
+-----------+-----+--------------+
| 高启强    |   3 | Java,Php,C++ |
| 陈书婷    |   2 | Php,C++      |
| 小虎      |   1 | C++          |
+-----------+-----+--------------+
```

每门课的选课人数：

```sql
select c.name, count(sc.id) cnt
from t_course c
left join t_student_course sc on c.id = sc.course_id
group by c.id, c.name;
-- Java 1、Php 2、C++ 3
```

## 6. 常见错误 ⚠️

### 6.1 漏写连接条件 → 笛卡尔积

```sql
select e.name, d.name from t_emp e, t_dept d;   -- 42 行，每个人「属于」每个部门
```

多表一多，很容易少写一个条件。用显式 `join ... on` 写，每个 `join` 后面紧跟 `on`，不容易漏。

### 6.2 一对多连接后，行数变多、count 翻倍

连接一对多的表，「一」那边的每一行会**按「多」那边的行数复制**。

```sql
-- 需求：有多少学生选了课？
select count(*) wrong, count(distinct s.id) right_cnt
from t_student s
join t_student_course sc on s.id = sc.student_id;
```
```
+-------+-----------+
| wrong | right_cnt |
+-------+-----------+
|     6 |         3 |
+-------+-----------+
```

只有 3 个学生，`count(*)` 数的是连接后的 6 行。同理，如果对「一」那边的金额字段 `sum`，金额也会被重复累加。

解决：
- 计数用 `count(distinct 主键)`。
- 更稳妥：先在子查询里把「多」的那边聚合好（每个学生一行），再去连接。

### 6.3 left join 后用 count(*) 统计，空的也算 1

```sql
select d.name, count(*) wrong, count(e.id) right_cnt
from t_dept d left join t_emp e on e.dept_id = d.id
group by d.id, d.name;
```
```
+-----------+-------+-----------+
| name      | wrong | right_cnt |
+-----------+-------+-----------+
| 研发部    |     2 |         2 |
| 市场部    |     1 |         1 |
| ...       |       |           |
| 测试部    |     1 |         0 |
+-----------+-------+-----------+
```

测试部没有员工，但 `left join` 会给它保留一行（员工列全是 `NULL`），`count(*)` 数到了这一行。要用 `count(右表的列)`，`NULL` 不计数。

### 6.4 列名重名不写表名

两张表都有 `name` 列，`select name` 会报错 `Column 'name' in field list is ambiguous`。多表查询时**所有列都带上表别名**，如 `e.name`、`d.name`。

### 6.5 select e.*, d.* 导致字段覆盖

两张表都有 `id`、`name`，后端框架把结果映射成对象时，同名字段可能互相覆盖。只查需要的列，重名的起别名：`d.name as dept_name`。

## 7. 小结

1. 多表查询 = 笛卡尔积 + 连接条件，n 张表至少 n - 1 个连接条件。
2. 内连接只保留两边都匹配的行；主表数据要完整显示时用 `left join`，统一写 `left join`，不写 `right join`。
3. MySQL 没有 `full join`，用左连接 `union` 右连接模拟。
4. `left join` 时，右表的过滤条件放 `on` 里；放 `where` 里会变成内连接。
5. 找「没有匹配」的数据：`not exists` 或 `left join ... is null`，**不要用 `not in`**，子查询里有 `NULL` 就查不出结果。
6. MySQL 8 里 `in` 和 `exists` 性能基本一样，按可读性选；需要右表的列时用 `join`。
7. 默认用 `union all`，需要去重时才用 `union`。
8. 一对多连接会复制行，计数用 `count(distinct ...)`；`left join` 后计数用 `count(右表列)`。
9. 多表查询所有列都带表别名，不用 `select *`。

---

上一章：[单表查询 🟢](02-single-table-query.md) · [目录](../README.md) · 下一章：[约束与表设计 🟢](04-table-design.md)

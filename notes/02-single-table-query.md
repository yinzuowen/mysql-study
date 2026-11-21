# 第 2 章 单表查询 🟢

> 本章练习：[00-execution-order.sql](../practice/00-execution-order.sql)、[03-row-column-transform.sql](../practice/03-row-column-transform.sql)、[t_student_subject_score.sql](../data/t_student_subject_score.sql)

> 后端接口里最常见的就是查询：列表页要分页、要按条件筛选、要排序；统计页要分组求和、求平均；排行榜要取每个分类的前几名。
> 写查询时最容易踩的坑：`where` 里用了 `select` 的别名报错、`group by` 报 `only_full_group_by`、分页翻页时数据重复或漏掉、`count` 结果和预期不一样。
> 本章从 `select` 的执行顺序讲起，把这些问题都讲清楚。
>
> 本章示例在本机 MySQL（版本 26.10）的 `itcast.t_user` 上实际跑过，输出是真实结果。`t_user` 有 24 行，字段：`id, name, phone, email, profession, age, gender('1' 男 '2' 女), status, createtime`。

## 1. select 的完整语法与执行顺序

```sql
select   字段列表            -- 5
from     表名                -- 1
where    条件               -- 2
group by 分组字段            -- 3
having   分组后的条件         -- 4
order by 排序字段            -- 6
limit    分页参数;           -- 7
```

**书写顺序**和**执行顺序**不一样，执行顺序是：

```
from -> where -> group by -> having -> select -> order by -> limit
```

理解了这个顺序，很多报错就能解释：

**`where` 里不能用 `select` 里起的别名**：`where` 在 `select` 之前执行，那时别名还不存在。

```sql
select profession, count(*) cnt from t_user where cnt > 1 group by profession;
-- ERROR 1054 (42S22): Unknown column 'cnt' in 'where clause'
```

**`order by` 可以用别名**：它在 `select` 之后执行。

```sql
select id, name, age * 2 double_age from t_user order by double_age desc limit 2;
```
```
+----+-----------+------------+
| id | name      | double_age |
+----+-----------+------------+
|  4 | 孙悟空    |        108 |
| 21 | 典韦      |        104 |
+----+-----------+------------+
```

**`having` 可以用别名**：按标准 SQL 不行，但 MySQL 做了扩展，`group by`、`having` 里都能用 `select` 的别名：

```sql
select profession p, count(*) cnt from t_user group by p having cnt >= 3 order by cnt desc;
```
```
+--------------+-----+
| p            | cnt |
+--------------+-----+
| 软件工程     |   4 |
| 工程造价     |   3 |
+--------------+-----+
```

> 为了能移植到其他数据库，`where` 和 `having` 里直接写表达式（如 `having count(*) >= 3`）更稳妥。

## 2. 条件查询

| 运算符 | 含义 | 例子 |
|---|---|---|
| `=`、`<>`（或 `!=`）、`>`、`>=`、`<`、`<=` | 比较 | `age >= 18` |
| `between a and b` | 在 a 到 b 之间，**包含两端** | `age between 20 and 23` |
| `in (...)` | 在列表中任意一个 | `profession in ('化工', '会计')` |
| `like` | 模糊匹配：`_` 匹配一个字符，`%` 匹配任意个字符 | `name like '_羽'` |
| `is null` / `is not null` | 是否为空 | `email is null` |
| `and`、`or`、`not` | 并且、或者、取反 | |

```sql
select id, name, age from t_user where age between 20 and 23;
```
```
+----+-----------+------+
| id | name      | age  |
+----+-----------+------+
|  1 | 吕布      |   23 |
|  5 | 花木兰    |   23 |
|  6 | 大乔      |   22 |
| 23 | 后羿      |   20 |
+----+-----------+------+
```

```sql
select id, name, profession from t_user where profession in ('化工', '会计');
```
```
+----+-----------+------------+
| id | name      | profession |
+----+-----------+------------+
| 12 | 荆轲      | 会计       |
| 18 | 嬴政      | 化工       |
|  8 | 程咬金    | 化工       |
+----+-----------+------------+
```

注意结果**不是按 id 排的**：这条查询走了 `profession` 上的索引，按索引的顺序返回。**没写 `order by`，返回顺序就没有保证**。

```sql
select id, name from t_user where name like '_羽';    -- 项羽：两个字，第二个是「羽」
select id, name from t_user where name like '%王%';   -- 兰陵王：包含「王」
```

`_` 本身是通配符，要匹配真正的下划线得转义：

```sql
select count(*) from t_user where email like '%\_%';   -- 1：只有 luna_love@sina.com 含下划线
select count(*) from t_user where email like '%_%';    -- 24：_ 匹配任意一个字符，所有邮箱都满足
```

`and` 优先级比 `or` 高，混用时**加括号**：

```sql
-- 想查「软件工程或化工」专业里年龄大于 30 的
select * from t_user where (profession = '软件工程' or profession = '化工') and age > 30;
```

## 3. 常用函数

### 3.1 字符串函数

```sql
select concat('Hello', ' ', 'MySQL') c, lower('ABC') l, upper('abc') u, lpad('7', 4, '0') lp,
       trim('  a b  ') t, substring('17799990000', 1, 3) sub, replace('a-b-c', '-', '/') r;
```
```
+-------------+------+------+------+------+------+-------+
| c           | l    | u    | lp   | t    | sub  | r     |
+-------------+------+------+------+------+------+-------+
| Hello MySQL | abc  | ABC  | 0007 | a b  | 177  | a/b/c |
+-------------+------+------+------+------+------+-------+
```

- `substring(str, start, len)` 的下标**从 1 开始**。
- `lpad` 常用来补零，比如把工号 `7` 变成 `0007`。
- `concat` 里只要有一个参数是 `null`，结果就是 `null`（见[第 1 章](01-basics.md)）。

### 3.2 数值函数

```sql
select ceil(1.2), floor(1.8), round(2.345, 2), round(2.5), truncate(2.345, 2), mod(7, 3),
       lpad(floor(rand() * 1000000), 6, '0') code;
```
```
+-----------+------------+-----------------+------------+--------------------+-----------+--------+
| ceil(1.2) | floor(1.8) | round(2.345, 2) | round(2.5) | truncate(2.345, 2) | mod(7, 3) | code   |
+-----------+------------+-----------------+------------+--------------------+-----------+--------+
|         2 |          1 |            2.35 |          3 |               2.34 |         1 | 573224 |
+-----------+------------+-----------------+------------+--------------------+-----------+--------+
```

- `ceil` 向上取整，`floor` 向下取整，`round` 四舍五入，`truncate` 直接截断。
- 最后一列是生成 6 位随机验证码的写法，每次结果不同。

除法相关的几个细节：

```sql
select 10 / 3, 10 div 3, 1 / 0, '10' + 5, 'abc' = 0;
```
```
+--------+----------+-------+----------+-----------+
| 10 / 3 | 10 div 3 | 1 / 0 | '10' + 5 | 'abc' = 0 |
+--------+----------+-------+----------+-----------+
| 3.3333 |        3 |  NULL |       15 |         1 |
+--------+----------+-------+----------+-----------+
```

- `/` 是普通除法，`div` 是整除。
- 除以 0 在 `select` 里返回 `null`，不报错。
- 字符串和数字运算时，字符串会被**隐式转成数字**：`'10'` 变成 10，`'abc'` 变成 0，所以 `'abc' = 0` 竟然成立。这也是「字符串列不加引号查询会让索引失效」的原因（见 [04-performance.sql](../practice/04-performance.sql)）。

### 3.3 日期函数

```sql
select now(), curdate(), curtime();   -- 2026-11-20 20:43:16 | 2026-11-20 | 20:43:16

select date_format(createtime, '%Y年%m月%d日') d,
       date_format(createtime, '%Y-%m-%d %H:%i:%s') full_dt,
       year(createtime) y,
       datediff('2026-11-20', createtime) days
from t_user where id = 1;
```
```
+-------------------+---------------------+------+------+
| d                 | full_dt             | y    | days |
+-------------------+---------------------+------+------+
| 2001年02月02日    | 2001-02-02 00:00:00 | 2001 | 9422 |
+-------------------+---------------------+------+------+
```

```sql
select date_add('2026-11-20', interval 30 day) plus30,
       date_sub('2026-11-20', interval 1 month) minus1m,
       last_day('2026-02-01') lastday,
       timestampdiff(year, '2001-02-02', '2026-11-20') years;
```
```
+------------+------------+------------+-------+
| plus30     | minus1m    | lastday    | years |
+------------+------------+------------+-------+
| 2026-12-20 | 2026-10-20 | 2026-02-28 |    25 |
+------------+------------+------------+-------+
```

| 函数 | 作用 |
|---|---|
| `date_format(日期, 格式)` | 格式化。`%Y` 四位年、`%m` 月、`%d` 日、`%H` 24 小时制、`%i` 分、`%s` 秒 |
| `datediff(d1, d2)` | d1 - d2 相差的天数 |
| `timestampdiff(单位, d1, d2)` | d2 - d1 相差多少个单位，如按年算年龄 |
| `date_add` / `date_sub` | 加减一段时间 |
| `last_day` | 当月最后一天 |

> ⚠️ 不要在 `where` 里对**索引列**套函数，比如 `where year(createtime) = 2001` 用不上 `createtime` 的索引。改成范围写法：`where createtime >= '2001-01-01' and createtime < '2002-01-01'`。

### 3.4 流程函数

```sql
select name, age,
       if(age >= 30, '30+', '30-') if_age,
       case when age < 25 then '青年' when age < 40 then '中年' else '老年' end age_group,
       case gender when '1' then '男' when '2' then '女' else '未知' end gender_text
from t_user where id in (1, 4, 5) order by id;
```
```
+-----------+------+--------+-----------+-------------+
| name      | age  | if_age | age_group | gender_text |
+-----------+------+--------+-----------+-------------+
| 吕布      |   23 | 30-    | 青年      | 男          |
| 孙悟空    |   54 | 30+    | 老年      | 男          |
| 花木兰    |   23 | 30-    | 青年      | 女          |
+-----------+------+--------+-----------+-------------+
```

| 函数 | 作用 |
|---|---|
| `if(条件, 真值, 假值)` | 二选一 |
| `ifnull(值, 默认值)` | 值为 `null` 时用默认值 |
| `case when 条件 then ... else ... end` | 多条件判断，从上往下匹配第一个成立的 |
| `case 字段 when 值 then ... end` | 按字段的值做映射，常用来把状态码翻译成文字 |

`case when` 配合聚合函数，就是[行转列](../practice/03-row-column-transform.sql)的写法。

## 4. 聚合函数与分组

### 4.1 聚合函数

| 函数 | 作用 |
|---|---|
| `count` | 计数 |
| `sum` / `avg` | 求和 / 平均 |
| `max` / `min` | 最大 / 最小 |

**所有聚合函数都会忽略 `null`**（`count(*)` 除外）。用一张临时表实测，4 个学生里有 2 个没有成绩：

```sql
create table tmp_ch02_score (id int primary key, name varchar(10), score int);
insert into tmp_ch02_score values (1, '甲', 90), (2, '乙', null), (3, '丙', 60), (4, '丁', null);
select count(*), count(score), sum(score), avg(score), avg(ifnull(score, 0)) from tmp_ch02_score;
```
```
+----------+--------------+------------+------------+-----------------------+
| count(*) | count(score) | sum(score) | avg(score) | avg(ifnull(score, 0)) |
+----------+--------------+------------+------------+-----------------------+
|        4 |            2 |        150 |    75.0000 |               37.5000 |
+----------+--------------+------------+------------+-----------------------+
```

`avg(score)` 是 150 / 2 = 75，不是 150 / 4。业务上「没成绩算 0 分」的话，要写成 `avg(ifnull(score, 0))`。

### 4.2 count(*)、count(1)、count(列) 的区别

在 `itcast.t_emp` 上实测（7 名员工，1 人没有部门）：

```sql
select count(*), count(1), count(dept_id), count(distinct dept_id) from t_emp;
```
```
+----------+----------+----------------+-------------------------+
| count(*) | count(1) | count(dept_id) | count(distinct dept_id) |
+----------+----------+----------------+-------------------------+
|        7 |        7 |              6 |                       5 |
+----------+----------+----------------+-------------------------+
```

| 写法 | 统计什么 |
|---|---|
| `count(*)` | 总行数。**统计行数就用它**，MySQL 对它有专门优化 |
| `count(1)` | 和 `count(*)` 一样，性能没有区别 |
| `count(列)` | 该列**不为 `null`** 的行数 |
| `count(distinct 列)` | 该列去重后、不为 `null` 的值的个数 |

### 4.3 group by

```sql
-- 每个专业的人数和平均年龄
select profession, count(*) cnt, avg(age) avg_age from t_user group by profession;
```

分组后，`select` 里**只能出现分组字段和聚合函数**。如果写了别的字段，MySQL 不知道该显示组里的哪一行：

```sql
select profession, name, count(*) from t_user group by profession;
-- ERROR 1055 (42000): Expression #2 of SELECT list is not in GROUP BY clause and contains nonaggregated column
-- 'itcast.t_user.name' which is not functionally dependent on columns in GROUP BY clause;
-- this is incompatible with sql_mode=only_full_group_by
```

这是 MySQL 5.7 起默认开启的 `only_full_group_by` 模式（`select @@sql_mode` 可以看到）。网上有教程教你把它关掉，**不要关**，它防止的是「结果随机」的错误。正确的做法：

- 这个字段确实要按它分组 → 加到 `group by` 里；
- 只想要组里的某个值 → 用聚合函数，如 `max(name)`；
- 真的随便哪个都行 → 用 `any_value(name)` 明确告诉 MySQL：

```sql
select profession, any_value(name) name, count(*) cnt from t_user group by profession order by cnt desc limit 3;
```
```
+--------------+-----------+-----+
| profession   | name      | cnt |
+--------------+-----------+-----+
| 软件工程     | 花木兰    |   4 |
| 工程造价     | 姜子牙    |   3 |
| 化工         | 嬴政      |   2 |
+--------------+-----------+-----+
```

- 想要「每组年龄最大的那个人」这种需求，`group by` 做不了，要用窗口函数（本章第 8 节）。

### 4.4 where 和 having 的区别

| | `where` | `having` |
|---|---|---|
| 执行时机 | 分组**之前** | 分组**之后** |
| 过滤的对象 | 行 | 组 |
| 能否用聚合函数 | 不能 | 能 |

```sql
-- 30 岁以上的员工里，人数 >= 2 的专业
select profession, count(*) from t_user where age > 30 group by profession having count(*) >= 2;
```
```
+--------------+----------+
| profession   | count(*) |
+--------------+----------+
| 化工         |        2 |
| 城市规划     |        2 |
| 工程造价     |        2 |
| 软件工程     |        2 |
+--------------+----------+
```

`age > 30` 是对每一行的条件，放 `where`；`count(*) >= 2` 是对每一组的条件，放 `having`。能放 `where` 的条件就**不要放 `having`**：先过滤掉行，参与分组的数据少，速度快。

## 5. 排序 order by

```sql
select 字段 from 表 order by 字段1 [asc|desc], 字段2 [asc|desc];   -- asc 升序（默认），desc 降序
```

多字段排序：先按第一个字段排，第一个字段相同时再按第二个排。

```sql
select gender, age, name from t_user order by gender, age desc limit 6;
```
```
+--------+------+-----------+
| gender | age  | name      |
+--------+------+-----------+
| 1      |   54 | 孙悟空    |
| 1      |   52 | 典韦      |
| 1      |   44 | 兰陵王    |
| 1      |   43 | 狂铁      |
| 1      |   43 | 项羽      |
| 1      |   38 | 程咬金    |
+--------+------+-----------+
```

狂铁和项羽都是 43 岁，谁在前面**没有保证**。需要稳定的顺序就再加一个唯一字段：`order by gender, age desc, id`。

### null 怎么排

MySQL 把 `null` 当成**最小值**：升序时在最前，降序时在最后。还是用前面的成绩临时表：

| 写法 | 结果顺序 |
|---|---|
| `order by score` | 乙(null)、丁(null)、丙(60)、甲(90) |
| `order by score desc` | 甲(90)、丙(60)、乙(null)、丁(null) |
| `order by score is null, score` | 丙(60)、甲(90)、乙(null)、丁(null) ← 升序但 null 放最后 |

`score is null` 对有值的行是 0、对 `null` 是 1，先按它排，`null` 就到后面去了。

## 6. 分页 limit

```sql
limit 起始索引, 每页条数        -- 起始索引从 0 开始
limit 每页条数 offset 起始索引  -- 等价写法
```

**起始索引 = (页码 - 1) × 每页条数**。每页 5 条：

```sql
select id, name, age from t_user order by age desc, id limit 0, 5;   -- 第 1 页
select id, name, age from t_user order by age desc, id limit 5, 5;   -- 第 2 页
```
```
第 1 页                          第 2 页
+----+-----------+------+        +----+-----------+------+
| id | name      | age  |        | id | name      | age  |
+----+-----------+------+        +----+-----------+------+
|  4 | 孙悟空    |   54 |        | 14 | 狂铁      |   43 |
| 21 | 典韦      |   52 |        | 15 | 貂蝉      |   40 |
| 20 | 安琪拉    |   51 |        |  8 | 程咬金    |   38 |
| 13 | 兰陵王    |   44 |        | 18 | 嬴政      |   38 |
|  9 | 项羽      |   43 |        | 17 | 芈月      |   35 |
+----+-----------+------+        +----+-----------+------+
```

总页数：

```sql
select count(*) total, ceil(count(*) / 5) pages from t_user;   -- total = 24, pages = 5
```

分页的两条规则：

1. **一定要有 `order by`**。没有排序时，每次返回的顺序由执行计划决定，翻页时可能出现重复或遗漏。
2. **排序字段要能唯一确定顺序**。上面项羽和狂铁同为 43 岁，正好被分在第 1 页和第 2 页的边界上；如果只写 `order by age desc`，两次查询可能一次把项羽放第 5 个、一次把狂铁放第 5 个，结果项羽出现两次、狂铁一次都没出现。末尾加上 `id` 就稳定了。

> `limit 100000, 10` 这种深分页会扫描并丢弃前 10 万行，很慢，优化方法见[第 8 章](08-sql-optimization.md)。

## 7. 去重 distinct

```sql
select distinct profession from t_user order by profession limit 5;   -- 会计、化工、国际贸易、土木工程、城市园林
select count(distinct profession) from t_user;                        -- 16 个不同的专业
```

`distinct` 作用于**后面所有字段的组合**，不是只作用于第一个字段：

```sql
select distinct gender, status from t_user order by gender, status;   -- 返回 10 种 (gender, status) 组合
```

## 8. 窗口函数入门（MySQL 8 起）

`group by` 会把一组压成一行；**窗口函数**在每一行上计算，同时保留所有行。典型用途：排名、每组取前 N 名、每行和组平均值对比。

```sql
函数() over (partition by 分组字段 order by 排序字段)
```

### 三个排名函数的区别

```sql
select name, age,
       row_number() over (order by age desc) rn,
       rank()       over (order by age desc) rk,
       dense_rank() over (order by age desc) drk
from t_user order by age desc, id limit 8;
```
```
+-----------+------+----+----+-----+
| name      | age  | rn | rk | drk |
+-----------+------+----+----+-----+
| 孙悟空    |   54 |  1 |  1 |   1 |
| 典韦      |   52 |  2 |  2 |   2 |
| 安琪拉    |   51 |  3 |  3 |   3 |
| 兰陵王    |   44 |  4 |  4 |   4 |
| 项羽      |   43 |  5 |  5 |   5 |
| 狂铁      |   43 |  6 |  5 |   5 |   <- 同龄
| 貂蝉      |   40 |  7 |  7 |   6 |   <- rank 跳过了 6，dense_rank 不跳
| 程咬金    |   38 |  8 |  8 |   7 |
+-----------+------+----+----+-----+
```

| 函数 | 并列时 | 序号 |
|---|---|---|
| `row_number()` | 不并列，硬排出先后 | 1, 2, 3, 4… |
| `rank()` | 并列同名次，后面**跳号** | 1, 2, 2, 4… |
| `dense_rank()` | 并列同名次，后面**不跳号** | 1, 2, 2, 3… |

### 每组取前 N 名

需求：每个专业年龄最大的 2 个人。`partition by profession` 表示按专业分别排名：

```sql
with t as (
    select name, profession, age,
           row_number() over (partition by profession order by age desc, id) rn
    from t_user
)
select profession, name, age, rn from t
where rn <= 2 and profession in ('软件工程', '工程造价', '城市规划')
order by profession, rn;
```
```
+--------------+-----------+------+----+
| profession   | name      | age  | rn |
+--------------+-----------+------+----+
| 城市规划     | 典韦      |   52 |  1 |
| 城市规划     | 安琪拉    |   51 |  2 |
| 工程造价     | 孙悟空    |   54 |  1 |
| 工程造价     | 兰陵王    |   44 |  2 |
| 软件工程     | 貂蝉      |   40 |  1 |
| 软件工程     | 妲己      |   31 |  2 |
+--------------+-----------+------+----+
```

窗口函数在 `select` 阶段才计算，所以**不能直接在 `where` 里用**，要像上面这样包一层（`with ... as` 是公用表表达式 CTE，相当于给子查询起个名字）：

```sql
select name, row_number() over (order by age) rn from t_user where rn <= 3;
-- ERROR 1054 (42S22): Unknown column 'rn' in 'where clause'
```

### 聚合函数也能当窗口函数用

每个员工的工资和本部门平均工资放在一起（`itcast.t_emp`）：

```sql
select name, salary, dept_id, avg(salary) over (partition by dept_id) dept_avg from t_emp order by dept_id, id;
```
```
+-----------+--------+---------+------------+
| name      | salary | dept_id | dept_avg   |
+-----------+--------+---------+------------+
| 熊杨      |   8000 |    NULL |  8000.0000 |
| 高雄      |  25000 |       1 | 14750.0000 |
| 王小焕    |   4500 |       1 | 14750.0000 |
| 汪瑜      |  20000 |       2 | 20000.0000 |
| ...                                      |
+-----------+--------+---------+------------+
```

用 `group by` 只能得到每个部门一行；窗口函数保留了每个员工。「查询工资比本部门平均工资高的员工」也可以这样写，不用子查询。

## 9. 常见错误

| 错误写法 | 问题 | 正确写法 |
|---|---|---|
| `where cnt > 1`（cnt 是别名） | `where` 先于 `select` 执行 | 写表达式，或改用 `having` |
| `where count(*) > 1` | `where` 里不能用聚合函数 | `having count(*) > 1` |
| `select name, count(*) ... group by profession` | 违反 `only_full_group_by` | 把 `name` 加进 `group by`，或用聚合函数 / `any_value` |
| `where dept_id = null` | 永远查不到 | `where dept_id is null` |
| `a = 1 or b = 2 and c = 3` | `and` 优先，结果不是你想的 | 加括号 |
| `like '%_%'` 想找下划线 | `_` 是通配符 | `like '%\_%'` |
| 分页不写 `order by`，或排序字段有重复值 | 翻页重复、遗漏 | `order by 业务字段, id` |
| `where year(createtime) = 2001` | 索引列套函数，索引失效 | 改成范围条件 |
| `where phone = 17799990000`（phone 是字符串） | 隐式类型转换，索引失效 | `where phone = '17799990000'` |
| `select *` | 多查无用字段，用不上覆盖索引 | 只查需要的列 |

## 10. 小结

1. 执行顺序是 `from → where → group by → having → select → order by → limit`，所以 `where` 不能用别名，`order by` 可以。
2. `between` 包含两端；`like` 里 `_` 匹配一个字符、`%` 匹配任意个；`and` 和 `or` 混用要加括号。
3. 字符串和数字比较会隐式转换（`'abc' = 0` 成立），条件里的类型要和字段类型一致。
4. 聚合函数忽略 `null`；统计行数用 `count(*)`；`count(列)` 不统计 `null`。
5. 开启 `only_full_group_by` 是好事，`select` 里只放分组字段和聚合函数。
6. 能用 `where` 过滤的就不要放到 `having`。
7. 分页 = `order by` 唯一确定的顺序 + `limit (页码 - 1) × 条数, 条数`。
8. 排名、每组前 N 名用窗口函数：`row_number`、`rank`、`dense_rank` 的区别在于并列时怎么编号。

---

上一章：[基础概念 🟢](01-basics.md) · [目录](../README.md) · 下一章：[多表查询 🟢](03-multi-table-query.md)

# SQL 性能分析与索引使用（课程笔记）
# 详细讲解和实测结果见 notes/07-index.md、notes/08-sql-optimization.md
# 示例基于 itcast.t_user（见 data/t_user.sql），表上的索引：
#   PRIMARY(id)、idx_user_name(name)、idx_user_phone(phone)（唯一）、idx_profession_age_status(profession, age, status)
# 在终端用 mysql < 文件 执行时要加 --default-character-set=utf8mb4，否则中文条件匹配不上

# 本机 MySQL 的 explain 默认输出树形格式，想看表格需要先执行：
set explain_format = traditional;


# ==================== 1. 查看执行频次 ====================
# Com_ 后面跟 7 个下划线，匹配 Com_select、Com_insert、Com_update、Com_delete 等
# 用来判断数据库是以查询为主还是以增删改为主
show global status like 'Com_______';


# ==================== 2. 慢查询日志 ====================
select @@slow_query_log;            # 是否开启
set global slow_query_log = 1;      # 开启慢查询日志
set global long_query_time = 2;     # 执行时间超过 2 秒的 SQL 视为慢查询，记录到日志
select @@slow_query_log_file;       # 日志文件位置

# set global 对之后新建立的连接生效，当前连接要重新连接才会用新的 long_query_time
# 日志文件位置：
#   教程里的 Linux 环境：/var/lib/mysql/localhost-slow.log
#   本机（Homebrew）：/opt/homebrew/var/mysql/<主机名>-slow.log


# ==================== 3. profile 详情 ====================
select @@have_profiling;            # 是否支持
set profiling = 1;                  # 开启（当前会话）
show profiles;                      # 查看每条 SQL 的耗时
show profile for query 1;           # 查看某条 SQL 各阶段的耗时，1 换成 show profiles 里的 Query_ID
show profile cpu for query 1;       # 同时查看 CPU 占用


# ==================== 4. explain 执行计划 ====================
explain select distinct * from t_student s, t_course c, t_student_course sc
where sc.student_id = s.id and sc.course_id = c.id;

# 重点关注的字段：
#   type           访问类型，性能由好到差：NULL > system > const > eq_ref > ref > range > index > ALL
#   possible_keys  可能用到的索引
#   key            实际用到的索引，NULL 表示没用索引
#   key_len        索引使用的字节数，可以用来判断联合索引用到了几列
#   rows           预估要扫描的行数
#   Extra          额外信息，如 Using index、Using where、Using index condition


# ==================== 5. 索引使用规则 ====================

# ---------- 5.1 最左前缀法则 ----------
# 联合索引要从最左边的列开始用，并且不能跳过中间的列：
#   最左边的列不存在，索引失效；
#   中间的列被跳过，后面的列不走索引。
explain select * from t_user where age = 18 and status = '1';
# type=ALL, key=NULL：没有最左列 profession，索引失效

explain select * from t_user where profession = '软件工程' and status = '1';
# key=idx_profession_age_status, key_len=83：跳过了 age，只用到 profession 一列

explain select * from t_user where profession = '软件工程' and age = 31 and status = '0';
# key_len=90：三列都用到了

# ---------- 5.2 范围查询 ----------
# 联合索引中出现范围查询（>、<）时，范围查询右侧的列不走索引。尽量用 >=、<=
explain select * from t_user where profession = '软件工程' and age > 30 and status = '0';
# type=range, key_len=85：只用到 profession 和 age，status 没用上

# ---------- 5.3 不要在索引列上进行运算操作，否则索引失效 ----------
explain select * from t_user where substring(phone, 10, 2) = '15';
# type=ALL：在 phone 上用了函数，索引失效

# ---------- 5.4 字符串不加引号，索引失效 ----------
explain select * from t_user where phone = '17799990015';
# type=const, key=idx_user_phone

explain select * from t_user where phone = 17799990015;
# type=ALL：发生了隐式类型转换，索引失效

# ---------- 5.5 头部模糊匹配，索引失效 ----------
explain select * from t_user where profession like '软件%';
# type=range：尾部模糊匹配，走索引

explain select * from t_user where profession like '%工程';
# type=ALL：头部模糊匹配，索引失效

# ---------- 5.6 or 连接的条件 ----------
# 用 or 连接的条件，只要有一侧的列没有索引，整个查询都不走索引
explain select * from t_user where id = 10 or age = 18;
# type=ALL：id 有主键索引，但 age 没有单独的索引，所以全表扫描
# 给 age 也建上索引后，这条查询才会走索引


# ==================== 6. SQL 提示 ====================
# 在 SQL 里告诉优化器用或不用哪个索引
explain select * from t_user use index(idx_profession_age_status) where profession = '软件工程';    # 建议使用，MySQL 可能不听
explain select * from t_user ignore index(idx_profession_age_status) where profession = '软件工程'; # 忽略，type=ALL
explain select * from t_user force index(idx_profession_age_status) where profession = '软件工程';  # 强制使用


# ==================== 7. 覆盖索引 ====================
# 查询的列都能在索引里找到，就不需要回表。尽量用覆盖索引，少用 select *
explain select id, profession from t_user where profession = '软件工程' and age = 31 and status = '0';
explain select id, profession, age, status from t_user where profession = '软件工程' and age = 31 and status = '0';
# Extra: Using where; Using index
# 需要的列都在 idx_profession_age_status 里（二级索引的叶子节点存了主键 id），不需要回表

explain select id, name, profession, age, status from t_user where profession = '软件工程' and age = 31 and status = '0';
# Extra: Using index condition
# name 不在这个索引里，需要回表查询

# 回表查询：在二级索引（也叫辅助索引）里拿不到需要的数据，要根据主键再去聚集索引（主键索引）里取


# ==================== 8. 前缀索引 ====================
# 当字段是字符串类型（varchar、text 等）且很长时，对整个字符串建索引会让索引变得很大，查询时浪费大量磁盘 I/O，影响查询效率
# 这时可以只对字符串的前几个字符建索引，大大节约索引空间，从而提高索引效率

# 前缀长度可以根据选择性来定：不重复的值占总行数的比例，越接近 1 越好
select count(distinct email) / count(*) from t_user;                  # 1.0000：整列的选择性
select count(distinct substring(email, 1, 5)) / count(*) from t_user; # 0.9583：取前 5 个字符的选择性

create index idx_user_email on t_user(email(5));


# ==================== 9. 索引设计原则 ====================
# 1. 针对数据量较大，且查询比较频繁的表建立索引。
# 2. 针对常作为查询条件（where）、排序（order by）、分组（group by）操作的字段建立索引。
# 3. 尽量选择区分度高的列作为索引，尽量建立唯一索引。区分度越高，使用索引的效率越高。
# 4. 如果是字符串类型的字段，字段的长度较长，可以针对字段的特点建立前缀索引（见第 8 节）。
# 5. 尽量使用联合索引，减少单列索引。查询时，联合索引很多时候可以覆盖索引，节省存储空间，避免回表，提高查询效率。
# 6. 要控制索引的数量。索引并不是多多益善，索引越多，维护索引结构的代价也就越大，会影响增删改的效率。
# 7. 如果索引列不能存储 null 值，请在建表时使用 not null 约束它。当优化器知道每列是否包含 null 值时，它可以更好地确定哪个索引最有效地用于查询。

# 区分度怎么看
select count(distinct gender) / count(*) from t_user;   # 0.0833：性别只有 1、2 两种值，区分度低，不适合单独建索引
select count(distinct phone)  / count(*) from t_user;   # 1.0000：手机号每行都不同，适合建（唯一）索引

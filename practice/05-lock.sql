# 锁（课程笔记）
# 详细讲解和实测结果见 notes/09-lock.md
# 示例基于 itcast.t_user：主键 id，普通索引 idx_user_name(name)，age 上没有单独的索引
# 在终端用 mysql < 文件 执行时要加 --default-character-set=utf8mb4，否则中文条件匹配不上


# ==================== 1. 全局锁 ====================
# 锁定整个数据库实例，加锁后整个库只能读，DML、DDL 都会被阻塞
# 典型场景：全库逻辑备份，保证备份出来的数据一致

# 加锁
flush tables with read lock;

# 解锁
unlock tables;

# 备份数据（mysqldump 是终端命令，不是 SQL，要在终端里执行）
# 加了全局锁之后再备份：
#   mysqldump -uroot -h127.0.0.1 itcast > data/itcast.sql
#
# InnoDB 不用加全局锁，加 --single-transaction 在快照下备份，备份期间业务可以正常读写：
#   mysqldump --single-transaction -uroot -h127.0.0.1 itcast > data/itcast.sql


# ==================== 2. 表级锁 ====================
# 每次操作锁住整张表，锁粒度大，发生锁冲突的概率高，并发度低

# ---------- 2.1 表锁 ----------
# 表共享读锁（read）：自己和别人都只能读，不能写
lock tables t_user read;
select * from t_user where id = 1;
unlock tables;

# 表独占写锁（write）：只有自己能读写，别人读写都要等
lock tables t_user write;
select * from t_user where id = 1;
unlock tables;

# ---------- 2.2 元数据锁（meta data lock，MDL） ----------
# 系统自动加，不需要手动加。作用：有事务在用这张表时，不让别人改表结构
#   select、select ... for share                     -> SHARED_READ
#   insert、update、delete、select ... for update    -> SHARED_WRITE
#   alter table ...                                  -> EXCLUSIVE（和其他所有 MDL 互斥）
# MDL 在事务提交后才释放：长事务没提交时执行 alter table，alter 会一直等，后面所有读写也跟着排队

# 查看元数据锁
begin;
select * from t_user where id = 1;
select object_type, object_schema, object_name, lock_type, lock_duration
from performance_schema.metadata_locks
where object_schema = 'itcast';
rollback;

# ---------- 2.3 意向锁 ----------
# 加行锁之前先在表上加意向锁，这样加表锁时不用逐行检查有没有行锁
# 意向共享锁（IS）：select ... for share 时加。与表共享锁（read）兼容，与表排他锁（write）互斥
# 意向排他锁（IX）：insert、update、delete、select ... for update 时加。与表共享锁（read）、表排他锁（write）都互斥
# 意向锁之间不会互斥

# 查看意向锁和行锁
begin;
select * from t_user where id = 1 for share;
select object_name, index_name, lock_type, lock_mode, lock_data
from performance_schema.data_locks;
rollback;


# ==================== 3. 行级锁 ====================
# 每次操作锁住对应的行，锁粒度小，并发度高
# InnoDB 的行锁是对索引上的索引项加锁实现的，而不是对记录加锁

# ---------- 3.1 行锁（Record Lock） ----------
# 锁定单个行记录，防止其他事务对此行进行 update、delete。在 RC、RR 隔离级别下支持
# 共享锁（S）：允许一个事务去读一行，阻止其他事务获得相同数据集的排他锁
# 排他锁（X）：允许获取排他锁的事务更新数据，阻止其他事务获得相同数据集的共享锁和排他锁
#
#   普通 select                          不加锁
#   select ... for share                 共享锁（S）
#   select ... for update                排他锁（X）
#   insert、update、delete               排他锁（X），自动加

begin;
select * from t_user where id = 1 for update;
select object_name, index_name, lock_type, lock_mode, lock_data
from performance_schema.data_locks;       # PRIMARY | RECORD | X,REC_NOT_GAP | 1
rollback;

# 注意：where 条件不走索引时，会对所有记录加锁，相当于锁住整张表
begin;
update t_user set status = '9' where age = 27;   # age 上没有单独的索引
select index_name, lock_mode, count(*)
from performance_schema.data_locks
where lock_type = 'RECORD'
group by index_name, lock_mode;                  # PRIMARY | X | 25（24 行 + supremum）
rollback;

# ---------- 3.2 间隙锁（Gap Lock） ----------
# 锁定索引记录间隙（不含该记录），确保索引记录间隙不变，防止其他事务在这个间隙进行 insert，产生幻读。在 RR 隔离级别下支持
# 间隙锁之间不互斥，它只阻止插入

# 唯一索引等值查询，记录不存在时，优化为间隙锁
begin;
select * from t_user where id = 30 for update;   # 最大 id 是 24
select index_name, lock_mode, lock_data
from performance_schema.data_locks
where lock_type = 'RECORD';                      # PRIMARY | X | supremum pseudo-record
rollback;

# ---------- 3.3 临键锁（Next-Key Lock） ----------
# 行锁和间隙锁的组合，同时锁住数据和数据前面的间隙。在 RR 隔离级别下支持

# 普通索引等值查询：锁住匹配记录（临键锁）和下一条记录前的间隙
begin;
update t_user set status = '9' where name = '白起';
select index_name, lock_mode, lock_data
from performance_schema.data_locks
where lock_type = 'RECORD';
# idx_user_name | X,GAP         | '程咬金', 8
# idx_user_name | X             | '白起', 10
# PRIMARY       | X,REC_NOT_GAP | 10
rollback;

# 范围查询：锁住范围内的记录和间隙
begin;
select id from t_user where id between 10 and 12 for update;
select index_name, lock_mode, lock_data
from performance_schema.data_locks
where lock_type = 'RECORD';
# PRIMARY | X,REC_NOT_GAP | 10
# PRIMARY | X             | 11
# PRIMARY | X             | 12
rollback;

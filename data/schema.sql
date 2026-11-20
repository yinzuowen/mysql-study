# 练习用表结构及测试数据
# 覆盖 01~03 中用到的所有表：t_dept、t_emp、t_salary_grade、t_student_score、t_student_score2

drop table if exists t_emp;
drop table if exists t_dept;
drop table if exists t_salary_grade;
drop table if exists t_student_score;
drop table if exists t_student_score2;

# 部门表
create table t_dept (
    id   int primary key auto_increment comment '部门ID',
    name varchar(50) not null comment '部门名称'
) engine = InnoDB default charset = utf8mb4 comment '部门表';

# 员工表
create table t_emp (
    id         int primary key auto_increment comment '员工ID',
    name       varchar(50)   not null comment '姓名',
    gender     char(1)       comment '性别',
    birth      date          comment '出生日期',
    salary     decimal(10, 2) comment '薪资',
    city       varchar(50)   comment '城市',
    manager_id int           comment '直属领导ID（关联 t_emp.id）',
    dept_id    int           comment '部门ID（关联 t_dept.id，可为空）'
) engine = InnoDB default charset = utf8mb4 comment '员工表';

# 薪资等级表
create table t_salary_grade (
    grade int primary key comment '等级',
    low   decimal(10, 2) not null comment '下限',
    high  decimal(10, 2) not null comment '上限'
) engine = InnoDB default charset = utf8mb4 comment '薪资等级表';

# 学生成绩表（纵表：一行一科，用于行转列）
create table t_student_score (
    student_id int         not null comment '学生ID',
    subject    varchar(20) not null comment '科目',
    score      int         comment '分数',
    primary key (student_id, subject)
) engine = InnoDB default charset = utf8mb4 comment '学生成绩表（纵表）';

# 学生成绩表（横表：一行一个学生，用于列转行）
create table t_student_score2 (
    student_id int primary key comment '学生ID',
    math       int comment '数学',
    english    int comment '英语'
) engine = InnoDB default charset = utf8mb4 comment '学生成绩表（横表）';


# ---------------- 测试数据 ----------------

# 人事部没有员工，用于“查询有员工的部门”
insert into t_dept (id, name) values
(1, '研发部'),
(2, '市场部'),
(3, '销售部'),
(4, '财务部'),
(5, '人事部');

insert into t_emp (id, name, gender, birth, salary, city, manager_id, dept_id) values
(1,  '张伟',   '男', '1980-03-12', 25000, '北京', null, 1),
(2,  '卢科',   '男', '1988-07-21', 18000, '北京', 1,    1),
(3,  '汪瑜',   '女', '1992-11-05', 12000, '上海', 1,    1),
(4,  '王小焕', '男', '1995-02-18', 9000,  '上海', 2,    1),
(5,  '吴利平', '女', '1985-06-30', 15000, '北京', null, 3),
(6,  '李娜',   '女', '1993-09-09', 11000, '北京', 1,    1),     -- 与卢科城市、直属领导相同
(7,  '赵强',   '男', '1991-04-14', 9000,  '广州', 5,    3),     -- 与王小焕性别、薪资相同
(8,  '孙丽',   '女', '1989-12-01', 12000, '上海', 5,    3),     -- 与汪瑜性别、薪资相同
(9,  '周杰',   '男', '1990-08-08', 13000, '深圳', null, 2),
(10, '陈晨',   '女', '1996-01-20', 8000,  '深圳', 9,    2),
(11, '刘洋',   '男', '1987-05-05', 10000, '北京', null, 4),
(12, '黄敏',   '女', '1994-03-03', 8500,  '北京', 11,   4),
(13, '郑凯',   '男', '1997-10-10', 6000,  '杭州', null, null);  -- 没有部门，用于左外连接

insert into t_salary_grade (grade, low, high) values
(1, 0,     3000),
(2, 3001,  5000),
(3, 5001,  8000),
(4, 8001,  10000),
(5, 10001, 15000),
(6, 15001, 20000),
(7, 20001, 50000);

insert into t_student_score (student_id, subject, score) values
(1, 'Math', 90), (1, 'English', 85),
(2, 'Math', 78), (2, 'English', 92),
(3, 'Math', 65), (3, 'English', 70);

insert into t_student_score2 (student_id, math, english) values
(1, 90, 85),
(2, 78, 92),
(3, 65, 70);

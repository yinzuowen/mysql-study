# itcast.t_student_subject_score 学生成绩表（一行一科）

drop table if exists t_student_subject_score;

create table t_student_subject_score (
    student_id char(4)     not null comment '学号',
    subject    varchar(10) not null comment '科目',
    score      int         not null comment '分数',
    primary key (student_id, subject),
    check (score between 0 and 100)
) engine = InnoDB default charset = utf8mb4 comment '学生成绩表（纵表）';

insert into t_student_subject_score (student_id, subject, score) values
('0001', 'chinese', 88),
('0002', 'chinese', 75),
('0003', 'chinese', 93),
('0004', 'chinese', 56),
('0005', 'chinese', 80),
('0006', 'chinese', 67),
('0007', 'chinese', 91),
('0008', 'chinese', 72),
('0001', 'math',    92),
('0002', 'math',    60),
('0003', 'math',    81),
('0004', 'math',    72),
('0005', 'math',    100),
('0006', 'math',    45),
('0007', 'math',    88),
('0008', 'math',    79),
('0001', 'english', 79),
('0002', 'english', 85),
('0003', 'english', 90),
('0004', 'english', 64),
('0005', 'english', 88),
('0006', 'english', 72),
('0007', 'english', 95),
('0008', 'english', 58);

# 行转列
select t.student_id,
max(case when subject = 'chinese' then score end) chinese,
max(case when subject = 'math' then score end) math,
max(case when subject = 'english' then score end) english
from t_student_subject_score t group by t.student_id;

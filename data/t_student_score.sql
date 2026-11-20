# itcast.t_student_score 学生成绩表（一行一个学生）

drop table if exists t_student_score;

create table t_student_score (
    student_id char(4) primary key comment '学号，如 0001',
    chinese    int not null comment '语文',
    math       int not null comment '数学',
    english    int not null comment '英语',
    check (chinese between 0 and 100),
    check (math between 0 and 100),
    check (english between 0 and 100)
) engine = InnoDB default charset = utf8mb4 comment '学生成绩表';

insert into t_student_score (student_id, chinese, math, english) values
('0001', 88, 92, 79),
('0002', 75, 60, 85),
('0003', 93, 81, 90),
('0004', 56, 72, 64),
('0005', 80, 100, 88),
('0006', 67, 45, 72),
('0007', 91, 88, 95),
('0008', 72, 79, 58);

# 列转行
select student_id, "chinese" as subject, chinese as score from t_student_score
union all
select student_id, "math" as subject, math as score from t_student_score
union all
select student_id, "english" as subject, english as score from t_student_score;

# 行转列
select student_id, max(case when subject="Math" then score end) as math, max(case when subject="English" then score end) as english from t_student_score group by student_id;

# 列转行
select student_id, 'math' as subject , math from t_student_score2
union all
select student_id, 'english' as subject , english from t_student_score2;

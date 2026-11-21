
# 行转列

select * from t_student_score;

select student_id, (case when subject="English" then score end) english from t_student_score;

select student_id, (case when subject="Math" then score end) math from t_student_score;

select student_id, (case when subject="English" then score end) english, (case when subject="Math" then score end) math from t_student_score;

select student_id, max(case when subject="English" then score end) english, max(case when subject="Math" then score end) math from t_student_score group by student_id;


# 列转行

select * from t_student_score2;

select student_id, "Owen" name, "math" subject, math from t_student_score2;

select student_id, "Owen" name, "english" subject, english from t_student_score2;

select student_id, "Owen" name, "math" subject, math from t_student_score2;
union all
select student_id, "Owen" name, "english" subject, english from t_student_score2;

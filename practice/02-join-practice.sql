# 加强练习

# 1.查询员工的信息及其部门信息（隐式内连接，就是多个表之间用逗号分隔）
select e.*, d.name from t_emp e, t_dept d where e.dept_id=d.id;

# 2.查询年龄>1990的员工信息及其部门信息（显式连接）
select e.*, d.name from t_emp e join t_dept d on e.dept_id=d.id where e.birth>'1990-01-01';

# 3.查询有员工的部门的信息
select distinct d.* from t_dept d, t_emp e where d.id=e.dept_id;

# 4.查询年龄>1990的员工信息，员工没有部门信息也要查询出来
select e.*, d.name from t_emp e left join t_dept d on e.dept_id=d.id where e.birth>'1990-01-01';

# 5.查询员工的薪资等级
select e.*, s.grade from t_emp e, t_salary_grade s where e.salary >= s.low and e.salary <= s.high;
select e.*, s.grade from t_emp e, t_salary_grade s where e.salary between s.low and s.high;

# 6.查询研发部所有员工的信息及其工资等级
select e.*, s.grade, d.name from t_emp e, t_salary_grade s, t_dept d where (e.salary between s.low and s.high) and e.dept_id = d.id and d.name="研发部";

# 7.查询研发部所有员工的平均工资
select avg(e.salary) from t_emp e, t_dept d where e.dept_id = d.id and d.name="研发部";

# 8.查询工资比吴利平高的员工信息
select e.* from t_emp e where e.salary > (select e.salary from t_emp e where e.name="吴利平");

# 9.查询工资比平均工资高的员工信息
select e.* from t_emp e where e.salary > (select avg(e.salary) from t_emp e);

# 10.查询工资比本部门平均工资高的员工信息
select e.* from t_emp e, (select avg(salary) avg_salary, dept_id from t_emp group by dept_id) e2 where e.dept_id=e2.dept_id and e.salary>e2.avg_salary;

select e1.* from t_emp e1 where e1.salary > (select avg(e2.salary) avg_salary from t_emp e2 where e1.dept_id=e2.dept_id);

# 11.查询所有的部门信息，并统计部门员工人数
select d.*, t.* from t_dept d left join (select count(*), dept_id from t_emp group by dept_id) t on d.id=t.dept_id;

select d.*, (select count(*) from t_emp e where e.dept_id=d.id) emp_count from t_dept d;

# 查询选修了Java课程的学生
select s.* from t_student s where s.id in (select sc.student_id from t_student_course sc where sc.course_id=(select c.id from t_course c where c.name="Java"));

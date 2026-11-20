# 标量子查询
# 查询销售部的所有员工
select * from t_emp where dept_id = (select id from t_dept where name="销售部");

# 列子查询
# 常用操作符：IN、NOT IN、ANY、SOME、ALL
# 1.查询销售部或市场部的所有员工
select * from t_emp where dept_id in (select id from t_dept where name in ("销售部","市场部"));

# 2.查询比财务部的所有员工的工资都高的员工
select * from t_emp where salary > all(select salary from t_emp where dept_id = (select id from t_dept where name = "财务部"));

# 3.查询比财务部的任一员工的工资高的员工
select * from t_emp where salary > any(select salary from t_emp where dept_id = (select id from t_dept where name = "研发部"));

# 行子查询
# 常用操作符：=、<>、IN、NOT IN
# 1.查询与“卢科”的城市和直属领导先通的员工
select * from t_emp where (city, manager_id) = (select city, manager_id from t_emp where name="卢科");

# 表子查询
# 常用操作符：IN
# 1.查询与“汪瑜“和“王小焕”的性别和薪资相同的员工
select * from t_emp where (gender, salary) in (select gender, salary from t_emp where name in ("汪瑜", "王小焕"));

# 2.查询出生日期1990-01-01之后的员工信息及其部门信息
select e.*, d.* from (select * from t_emp where birth > "1990-01-01") e left join t_dept d on e.dept_id = d.id;

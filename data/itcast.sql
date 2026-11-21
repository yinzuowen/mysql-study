-- MySQL dump 10.13  Distrib 26.10.0, for macos27.0 (arm64)
--
-- Host: localhost    Database: itcast
-- ------------------------------------------------------
-- Server version	26.10.0

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
SET @MYSQLDUMP_TEMP_LOG_BIN = @@SESSION.SQL_LOG_BIN;
SET @@SESSION.SQL_LOG_BIN= 0;

--
-- GTID state at the beginning of the backup 
--

SET @@GLOBAL.GTID_PURGED=/*!80000 '+'*/ 'f5c3c094-de4c-11f1-9399-e482ded48b3c:1-10421';

--
-- Table structure for table `t_account`
--

DROP TABLE IF EXISTS `t_account`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_account` (
  `id` varchar(4) DEFAULT NULL,
  `name` varchar(10) DEFAULT NULL,
  `balance` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_account`
--

LOCK TABLES `t_account` WRITE;
/*!40000 ALTER TABLE `t_account` DISABLE KEYS */;
INSERT INTO `t_account` VALUES ('0001','张三',3000),('0002','李四',3000);
/*!40000 ALTER TABLE `t_account` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_course`
--

DROP TABLE IF EXISTS `t_course`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_course` (
  `id` int NOT NULL AUTO_INCREMENT COMMENT '课程编号',
  `name` varchar(50) NOT NULL COMMENT '课程名称',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_course`
--

LOCK TABLES `t_course` WRITE;
/*!40000 ALTER TABLE `t_course` DISABLE KEYS */;
INSERT INTO `t_course` VALUES (1,'Java'),(2,'Php'),(3,'C++');
/*!40000 ALTER TABLE `t_course` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_dept`
--

DROP TABLE IF EXISTS `t_dept`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_dept` (
  `id` int NOT NULL AUTO_INCREMENT COMMENT '部门ID',
  `name` varchar(50) NOT NULL COMMENT '部门名称',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=52 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='部门表';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_dept`
--

LOCK TABLES `t_dept` WRITE;
/*!40000 ALTER TABLE `t_dept` DISABLE KEYS */;
INSERT INTO `t_dept` VALUES (1,'研发部'),(2,'市场部'),(3,'销售部'),(4,'财务部'),(5,'人事部');
/*!40000 ALTER TABLE `t_dept` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_emp`
--

DROP TABLE IF EXISTS `t_emp`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_emp` (
  `id` int NOT NULL AUTO_INCREMENT COMMENT '员工ID',
  `name` varchar(50) NOT NULL COMMENT '姓名',
  `gender` char(1) DEFAULT NULL COMMENT '性别',
  `birth` date DEFAULT NULL COMMENT '出生日期',
  `salary` decimal(10,2) DEFAULT NULL COMMENT '薪资',
  `city` varchar(50) DEFAULT NULL COMMENT '城市',
  `manager_id` int DEFAULT NULL COMMENT '直属领导ID（关联 t_emp.id）',
  `dept_id` int DEFAULT NULL COMMENT '部门ID（关联 t_dept.id，可为空）',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=52 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='员工表';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_emp`
--

LOCK TABLES `t_emp` WRITE;
/*!40000 ALTER TABLE `t_emp` DISABLE KEYS */;
INSERT INTO `t_emp` VALUES (1,'张伟','男','1980-03-12',25000.00,'北京',NULL,1),(2,'卢科','男','1988-07-21',18000.00,'北京',1,1),(3,'汪瑜','女','1992-11-05',12000.00,'上海',1,1),(4,'王小焕','男','1995-02-18',9000.00,'上海',2,1),(5,'吴利平','女','1985-06-30',15000.00,'北京',NULL,3),(6,'李娜','女','1993-09-09',11000.00,'北京',1,1),(7,'赵强','男','1991-04-14',9000.00,'广州',5,3),(8,'孙丽','女','1989-12-01',12000.00,'上海',5,3),(9,'周杰','男','1990-08-08',13000.00,'深圳',NULL,2),(10,'陈晨','女','1996-01-20',8000.00,'深圳',9,2),(11,'刘洋','男','1987-05-05',10000.00,'北京',NULL,4),(12,'黄敏','女','1994-03-03',8500.00,'北京',11,4),(13,'郑凯','男','1997-10-10',6000.00,'杭州',NULL,NULL);
/*!40000 ALTER TABLE `t_emp` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_salary_grade`
--

DROP TABLE IF EXISTS `t_salary_grade`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_salary_grade` (
  `grade` int NOT NULL COMMENT '等级',
  `low` decimal(10,2) NOT NULL COMMENT '下限',
  `high` decimal(10,2) NOT NULL COMMENT '上限',
  PRIMARY KEY (`grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='薪资等级表';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_salary_grade`
--

LOCK TABLES `t_salary_grade` WRITE;
/*!40000 ALTER TABLE `t_salary_grade` DISABLE KEYS */;
INSERT INTO `t_salary_grade` VALUES (1,0.00,3000.00),(2,3001.00,5000.00),(3,5001.00,8000.00),(4,8001.00,10000.00),(5,10001.00,15000.00),(6,15001.00,20000.00),(7,20001.00,50000.00);
/*!40000 ALTER TABLE `t_salary_grade` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_student`
--

DROP TABLE IF EXISTS `t_student`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_student` (
  `id` int NOT NULL AUTO_INCREMENT COMMENT '学生编号',
  `name` varchar(50) NOT NULL COMMENT '学生名称',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_student`
--

LOCK TABLES `t_student` WRITE;
/*!40000 ALTER TABLE `t_student` DISABLE KEYS */;
INSERT INTO `t_student` VALUES (1,'高启强'),(2,'陈书婷'),(3,'小虎');
/*!40000 ALTER TABLE `t_student` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_student_course`
--

DROP TABLE IF EXISTS `t_student_course`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_student_course` (
  `id` int NOT NULL AUTO_INCREMENT,
  `student_id` int NOT NULL COMMENT '学生编号',
  `course_id` int NOT NULL COMMENT '课程编号',
  PRIMARY KEY (`id`),
  KEY `fk_student_id` (`student_id`),
  KEY `fk_course_id` (`course_id`),
  CONSTRAINT `fk_course_id` FOREIGN KEY (`course_id`) REFERENCES `t_course` (`id`),
  CONSTRAINT `fk_student_id` FOREIGN KEY (`student_id`) REFERENCES `t_student` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_student_course`
--

LOCK TABLES `t_student_course` WRITE;
/*!40000 ALTER TABLE `t_student_course` DISABLE KEYS */;
INSERT INTO `t_student_course` VALUES (1,1,1),(2,1,2),(3,1,3),(4,2,2),(5,2,3),(6,3,3);
/*!40000 ALTER TABLE `t_student_course` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_student_score`
--

DROP TABLE IF EXISTS `t_student_score`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_student_score` (
  `student_id` int NOT NULL COMMENT '学生ID',
  `subject` varchar(20) NOT NULL COMMENT '科目',
  `score` int DEFAULT NULL COMMENT '分数',
  PRIMARY KEY (`student_id`,`subject`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='学生成绩表（纵表）';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_student_score`
--

LOCK TABLES `t_student_score` WRITE;
/*!40000 ALTER TABLE `t_student_score` DISABLE KEYS */;
INSERT INTO `t_student_score` VALUES (1,'English',85),(1,'Math',90),(2,'English',92),(2,'Math',78),(3,'English',70),(3,'Math',65);
/*!40000 ALTER TABLE `t_student_score` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_student_score2`
--

DROP TABLE IF EXISTS `t_student_score2`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_student_score2` (
  `student_id` int NOT NULL COMMENT '学生ID',
  `math` int DEFAULT NULL COMMENT '数学',
  `english` int DEFAULT NULL COMMENT '英语',
  PRIMARY KEY (`student_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='学生成绩表（横表）';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_student_score2`
--

LOCK TABLES `t_student_score2` WRITE;
/*!40000 ALTER TABLE `t_student_score2` DISABLE KEYS */;
INSERT INTO `t_student_score2` VALUES (1,90,85),(2,78,92),(3,65,70);
/*!40000 ALTER TABLE `t_student_score2` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_student_subject_score`
--

DROP TABLE IF EXISTS `t_student_subject_score`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_student_subject_score` (
  `student_id` char(4) NOT NULL COMMENT '学号',
  `subject` varchar(10) NOT NULL COMMENT '科目',
  `score` int NOT NULL COMMENT '分数',
  PRIMARY KEY (`student_id`,`subject`),
  CONSTRAINT `t_student_subject_score_chk_1` CHECK ((`score` between 0 and 100))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='学生成绩表（纵表）';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_student_subject_score`
--

LOCK TABLES `t_student_subject_score` WRITE;
/*!40000 ALTER TABLE `t_student_subject_score` DISABLE KEYS */;
INSERT INTO `t_student_subject_score` VALUES ('0001','chinese',88),('0001','english',79),('0001','math',92),('0002','chinese',75),('0002','english',85),('0002','math',60),('0003','chinese',93),('0003','english',90),('0003','math',81),('0004','chinese',56),('0004','english',64),('0004','math',72),('0005','chinese',80),('0005','english',88),('0005','math',100),('0006','chinese',67),('0006','english',72),('0006','math',45),('0007','chinese',91),('0007','english',95),('0007','math',88),('0008','chinese',72),('0008','english',58),('0008','math',79);
/*!40000 ALTER TABLE `t_student_subject_score` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `t_user`
--

DROP TABLE IF EXISTS `t_user`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `t_user` (
  `id` int NOT NULL AUTO_INCREMENT COMMENT '主键',
  `name` varchar(10) NOT NULL COMMENT '姓名',
  `phone` varchar(11) NOT NULL COMMENT '手机号',
  `email` varchar(100) DEFAULT NULL COMMENT '邮箱',
  `profession` varchar(20) DEFAULT NULL COMMENT '专业',
  `age` tinyint unsigned DEFAULT NULL COMMENT '年龄',
  `gender` char(1) DEFAULT NULL COMMENT '性别：1 男，2 女',
  `status` char(1) DEFAULT NULL COMMENT '状态',
  `createtime` datetime DEFAULT NULL COMMENT '创建时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_phone` (`phone`),
  KEY `idx_user_name` (`name`),
  KEY `idx_profession_age_status` (`profession`,`age`,`status`)
) ENGINE=InnoDB AUTO_INCREMENT=25 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='用户表';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `t_user`
--

LOCK TABLES `t_user` WRITE;
/*!40000 ALTER TABLE `t_user` DISABLE KEYS */;
INSERT INTO `t_user` VALUES (1,'吕布','17799990000','lvbu666@163.com','软件工程',23,'1','6','2001-02-02 00:00:00'),(2,'曹操','17799990001','caocao666@qq.com','通讯工程',33,'1','0','2001-03-05 00:00:00'),(3,'赵云','17799990002','17799990@139.com','英语',34,'1','2','2002-03-02 00:00:00'),(4,'孙悟空','17799990003','17799990@sina.com','工程造价',54,'1','0','2001-07-02 00:00:00'),(5,'花木兰','17799990004','19980729@sina.com','软件工程',23,'2','1','2001-04-22 00:00:00'),(6,'大乔','17799990005','daqiao666@sina.com','舞蹈',22,'2','0','2001-02-07 00:00:00'),(7,'露娜','17799990006','luna_love@sina.com','应用数学',24,'2','0','2001-02-08 00:00:00'),(8,'程咬金','17799990007','chengyaojin@163.com','化工',38,'1','5','2001-05-23 00:00:00'),(9,'项羽','17799990008','xiaoyu666@qq.com','金属材料',43,'1','0','2001-09-18 00:00:00'),(10,'白起','17799990009','baiqi666@sina.com','机械工程及其自动化',27,'1','2','2001-08-16 00:00:00'),(11,'韩信','17799990010','hanxin520@163.com','无机非金属材料工程',27,'1','0','2001-06-12 00:00:00'),(12,'荆轲','17799990011','jingke123@163.com','会计',29,'1','0','2001-05-11 00:00:00'),(13,'兰陵王','17799990012','lanlinwang666@126.com','工程造价',44,'1','1','2001-04-09 00:00:00'),(14,'狂铁','17799990013','kuangtie@sina.com','应用数学',43,'1','2','2001-04-10 00:00:00'),(15,'貂蝉','17799990014','84958948374@qq.com','软件工程',40,'2','3','2001-02-12 00:00:00'),(16,'妲己','17799990015','2783238293@qq.com','软件工程',31,'2','0','2001-01-30 00:00:00'),(17,'芈月','17799990016','xiaomin2001@sina.com','工业经济',35,'2','0','2000-05-03 00:00:00'),(18,'嬴政','17799990017','8839434342@qq.com','化工',38,'1','1','2001-08-08 00:00:00'),(19,'狄仁杰','17799990018','jujiamlm8166@163.com','国际贸易',30,'1','0','2007-03-12 00:00:00'),(20,'安琪拉','17799990019','jdodm1h@126.com','城市规划',51,'2','0','2001-08-15 00:00:00'),(21,'典韦','17799990020','ycaunanjian@163.com','城市规划',52,'1','2','2000-04-12 00:00:00'),(22,'廉颇','17799990021','lianpo321@126.com','土木工程',19,'1','3','2002-07-18 00:00:00'),(23,'后羿','17799990022','altycj2000@139.com','城市园林',20,'1','0','2002-03-10 00:00:00'),(24,'姜子牙','17799990023','37483844@qq.com','工程造价',29,'1','4','2003-05-26 00:00:00');
/*!40000 ALTER TABLE `t_user` ENABLE KEYS */;
UNLOCK TABLES;
SET @@SESSION.SQL_LOG_BIN = @MYSQLDUMP_TEMP_LOG_BIN;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-11-21 15:29:09

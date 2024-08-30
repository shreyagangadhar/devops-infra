provider "aws" {
  region = "us-west-2"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "main-vpc"
  }
}

# Create Public Subnet
resource "aws_subnet" "public" {
  vpc_id                 = aws_vpc.main.id
  cidr_block             = "10.0.1.0/24"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "public-subnet"
  }
}

# Create Private Subnet
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  
  tags = {
    Name = "private-subnet"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Create Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate Public Route Table with Public Subnet
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create Security Group for Public Instance
resource "aws_security_group" "public_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public-sg"
  }
}

# Create Security Group for Private RDS Instance
resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-sg"
  }
}

# IAM Role for EC2 Instance with RDS and ECR Full Access
resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
  
  tags = {
    Name = "EC2Role"
  }
}

# RDS Full Access Policy
resource "aws_iam_policy" "rds_full_access_policy" {
  name        = "rds-full-access"
  description = "Provides full access to RDS"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "rds:*",
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# ECR Full Access Policy
resource "aws_iam_policy" "ecr_full_access_policy" {
  name        = "ecr-full-access"
  description = "Provides full access to ECR"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "ecr:*",
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Attach RDS Full Access Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "rds_access_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.rds_full_access_policy.arn
}

# Attach ECR Full Access Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "ecr_access_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ecr_full_access_policy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# Launch EC2 Instance in Public Subnet
resource "aws_instance" "app_server" {
  ami                  = "ami-02d3770deb1c746ec"  # Amazon Linux 2
  instance_type        = "t2.micro"
  key_name             = "test-tf"
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  subnet_id            = aws_subnet.public.id

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "AppServer"
  }
}

# Create DB Subnet Group
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"  
  availability_zone = "us-west-2a"  

  tags = {
    Name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"  
  availability_zone = "us-west-2b"  

  tags = {
    Name = "private-subnet-b"
  }
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "db_subnet_group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "db-subnet-group"
  }
}

# Launch RDS Instance in Private Subnet
resource "aws_db_instance" "app_db" {
  engine            = "postgres"
  engine_version    = "15.7"
  parameter_group_name = "default.postgres15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  identifier        = "app-db"  
  username          = "postgres"
  manage_master_user_password = true
  db_subnet_group_name = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  multi_az          = true
  publicly_accessible = false

  tags = {
    Name = "AppDB"
  }
}

resource "aws_key_pair" "hostkey" {
  key_name   = "test-tf"
  public_key = "${file("${path.module}/keypair.pub")}"
}

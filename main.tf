resource "aws_vpc" "dev" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "DEV-VPC"
  }
}
resource "aws_subnet" "public-sn-1a" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.0.0.0/26"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-sn-1a"
  }
}
resource "aws_subnet" "private-sn-1a" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = "10.0.0.64/26"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-sn-1a"
  }
}
resource "aws_subnet" "public-sn-1b" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = "10.0.0.128/26"
  availability_zone = "us-east-1b"
  tags = {
    Name = "public-sn-1b"
  }
}
resource "aws_subnet" "private-sn-1b" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = "10.0.0.192/26"
  availability_zone = "us-east-1b"
  tags = {
    Name = "private-sn-1b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev.id
  tags = {
    Name = "dev-igw"
  }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public-sn-1a.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public-sn-1b.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_eip" "eip" {

  domain = "vpc"
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public-sn-1a.id

  tags = {
    Name = "ngw"
  }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "pa" {
  subnet_id      = aws_subnet.private-sn-1a.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_route_table_association" "pb" {
  subnet_id      = aws_subnet.private-sn-1b.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_security_group" "allow_tls" {
  name        = "dev-vpc-web-sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.dev.id

  ingress = [
    {
      description      = "HTTP"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false


    },
    {
      description      = "SSH"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false

    }
  ]

  tags = {
    Name = "dev-vpc-web-sg"
  }
}

resource "aws_instance" "web" {
  ami             = "ami-09538990a0c4fe9be"
  instance_type   = "t3.micro"
  key_name        = "key"
  subnet_id       = aws_subnet.public-sn-1a.id
  security_groups = [aws_security_group.allow_tls.id]
  user_data       = <<EOF
  #!/bin/bash
    yum update -y
    yum install -y httpd 
    systemctl start httpd
    systemctl enable httpd
    echo "<h1> $(hostname -f) </h1>"  >/var/www/html/index.html
    EOF

  tags = {
    Name = "web-server"
  }
}

resource "aws_lb" "alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls.id]
  subnets            = [aws_subnet.public-sn-1a.id,aws_subnet.public-sn-1b.id]

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "test" {
  name     = "my-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dev.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}
resource "aws_lb_target_group_attachment" "a1" {
  target_group_arn = aws_lb_target_group.test.arn
  target_id        = aws_instance.web.id
  port             = 80
}
resource "aws_s3_bucket" "example" {
  bucket = "mys3fromterrafrombucket2015"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}
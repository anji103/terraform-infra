locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  name = "${var.project_name}-${var.environment}"
}
 
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-vpc" }
}
 
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-igw" }
}
 
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public-${count.index + 1}", Tier = "public" }
}
 
resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]
  tags = { Name = "${local.name}-app-${count.index + 1}", Tier = "private-app" }
}
 
resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = local.azs[count.index]
  tags = { Name = "${local.name}-db-${count.index + 1}", Tier = "private-db" }
}
 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route { cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.this.id }
  tags = { Name = "${local.name}-public-rt" }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
 
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
  tags   = { Name = "${local.name}-nat-eip-${count.index + 1}" }
}
resource "aws_nat_gateway" "this" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.this]
  tags          = { Name = "${local.name}-nat-${count.index + 1}" }
}
resource "aws_route_table" "app" {
  count  = 2
  vpc_id = aws_vpc.this.id
  route { cidr_block = "0.0.0.0/0"
nat_gateway_id = aws_nat_gateway.this[count.index].id }
  tags = { Name = "${local.name}-app-rt-${count.index + 1}" }
}
resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-db-rt" }
}
resource "aws_route_table_association" "db" {
  count          = 2
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
 
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Public HTTPS ingress to ALB"
  vpc_id      = aws_vpc.this.id
  ingress { description = "HTTPS"
from_port = 443
to_port = 443
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "HTTP only from ALB"
  vpc_id      = aws_vpc.this.id
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress { from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "MySQL only from app tier"
  vpc_id      = aws_vpc.this.id
  ingress {
    description     = "MySQL from application instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress { from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"] }
}
 
resource "aws_s3_bucket" "alb_logs" {
  bucket_prefix = "${local.name}-alb-logs-"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-alb-logs"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = var.log_retention_days }
  }
}
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid = "AllowALBLogDelivery",
      Effect = "Allow",
      Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" },
      Action = "s3:PutObject",
      Resource = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
      Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
    }]
  })
}
 
resource "aws_lb" "this" {
  name               = substr("${local.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }
  depends_on = [aws_s3_bucket_policy.alb_logs]
}
resource "aws_lb_target_group" "app" {
  name     = substr("${local.name}-tg", 0, 32)
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id
  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol           = "HTTPS"
  certificate_arn    = var.acm_certificate_arn
  ssl_policy         = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
 
resource "aws_iam_role" "ec2" {
  name = "${local.name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "ec2_secrets" {
  name = "${local.name}-read-db-secret"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["secretsmanager:GetSecretValue"],
      Resource = aws_secretsmanager_secret.db.arn
    }]
  })
}
resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.ec2.name
}
 
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/database"
  description             = "Database connection credentials for ${local.name}"
  recovery_window_in_days = 7
}
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
  })
}
 
resource "aws_db_subnet_group" "db" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
}
resource "aws_db_instance" "mysql" {
  identifier                 = substr("${local.name}-mysql", 0, 63)
  engine                     = "mysql"
  engine_version             = "8.0"
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.db_name
  username                   = var.db_username
  password                   = random_password.db.result
  manage_master_user_password = false
  db_subnet_group_name       = aws_db_subnet_group.db.name
  vpc_security_group_ids     = [aws_security_group.db.id]
  publicly_accessible        = false
  multi_az                   = var.db_multi_az
  backup_retention_period    = 7
  deletion_protection        = false
  skip_final_snapshot        = true
  apply_immediately          = false
  auto_minor_version_upgrade = true
  tags = { Name = "${local.name}-mysql" }
}
 
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  iam_instance_profile { name = aws_iam_instance_profile.ec2.name }
  vpc_security_group_ids = [aws_security_group.app.id]
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    project_name = local.name
  }))
  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${local.name}-app" }
  }
}
resource "aws_autoscaling_group" "app" {
  name                = "${local.name}-asg"
  min_size            = var.min_size
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  vpc_zone_identifier = aws_subnet.app[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 180
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }
  depends_on = [aws_lb_listener.https]
}
 
resource "aws_s3_bucket" "app_storage" {
  bucket_prefix = "${local.name}-app-storage-"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "app_storage" {
  bucket                  = aws_s3_bucket.app_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "app_storage" {
  bucket = aws_s3_bucket.app_storage.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}

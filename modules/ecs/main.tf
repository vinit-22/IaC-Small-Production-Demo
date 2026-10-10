# ---------------- Cluster ----------------
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------------- EC2 capacity (Launch Template + ASG) ----------------
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Public HTTP to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.name}-ecs-ec2-sg"
  description = "ECS hosts: only ALB can reach dynamic ports"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ALB to dynamic host ports"
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "ecs" {
  name_prefix            = "${var.name}-ecs-"
  image_id               = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.this.name}" >> /etc/ecs/ecs.config
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-ecs-host" }
  }
}

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.name}-ecs-asg"
  min_size            = var.asg_min
  max_size            = var.asg_max
  desired_capacity    = var.asg_min
  vpc_zone_identifier = var.app_subnet_ids

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-ecs-host"
    propagate_at_launch = true
  }
}

# ---------------- ALB ----------------
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "svc" {
  for_each             = var.services
  name                 = "${var.name}-${each.key}"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = var.vpc_id
  deregistration_delay = 10

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Default action: weighted forward 50/50 to both target groups
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    forward {
      dynamic "target_group" {
        for_each = aws_lb_target_group.svc
        content {
          arn    = target_group.value.arn
          weight = 50
        }
      }
    }
  }
}

# Direct path routes so each service can also be tested on its own
resource "aws_lb_listener_rule" "direct" {
  for_each     = var.services
  listener_arn = aws_lb_listener.http.arn
  priority     = 10 + index(sort(keys(var.services)), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }
  condition {
    path_pattern {
      values = ["/${each.key}", "/${each.key}/*"]
    }
  }
}

# ---------------- Logs ----------------
resource "aws_cloudwatch_log_group" "svc" {
  for_each          = var.services
  name              = "/ecs/${var.name}-${each.key}"
  retention_in_days = 7
}

# ---------------- Task definitions + services ----------------
resource "aws_ecs_task_definition" "svc" {
  for_each                 = var.services
  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = var.task_execution_role_arn
  cpu                      = 128
  memory                   = 128

  container_definitions = jsonencode([{
    name       = "nginx"
    image      = "public.ecr.aws/nginx/nginx:stable"
    essential  = true
    entryPoint = ["/bin/sh", "-c"]
    # Init step: overwrite default page, also serve it under /<service>/, then run nginx
    command = ["echo '${each.value}' > /usr/share/nginx/html/index.html && mkdir -p /usr/share/nginx/html/${each.key} && cp /usr/share/nginx/html/index.html /usr/share/nginx/html/${each.key}/index.html && exec nginx -g 'daemon off;'"]
    portMappings = [{ containerPort = 80, hostPort = 0, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.svc[each.key].name
        awslogs-region        = var.region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}

resource "aws_ecs_service" "svc" {
  for_each        = var.services
  name            = each.key
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.svc[each.key].arn
  desired_count   = 2
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = aws_lb_target_group.svc[each.key].arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http, aws_autoscaling_group.ecs]

  lifecycle {
    ignore_changes = [desired_count] # managed by app autoscaling
  }
}

# ---------------- Task autoscaling (bonus) ----------------
resource "aws_appautoscaling_target" "svc" {
  for_each           = var.services
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.svc[each.key].name}"
  min_capacity       = 2
  max_capacity       = 3
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each           = var.services
  name               = "${var.name}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.svc[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.svc[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.svc[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    target_value = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------- 1. EC2 instance role (ECS agent + SSM) ----------
resource "aws_iam_role" "ec2" {
  name               = "${var.name}-ec2-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Managed policies: AWS-maintained, required for the ECS agent and SSM Session Manager
resource "aws_iam_role_policy_attachment" "ec2_ecs" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2-instance-profile"
  role = aws_iam_role.ec2.name
}

# ---------- 2. ECS task execution role (scoped inline) ----------
resource "aws_iam_role" "task_execution" {
  name               = "${var.name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "task_execution" {
  statement {
    sid       = "WriteEcsLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/ecs/${var.name}-*:*"]
  }
  # Add ecr:GetAuthorizationToken / ecr:BatchGetImage here if you move to ECR images.
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "ecs-task-execution-logs"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

# ---------- 3. Lambda execution role (S3 PutObject only + own logs) ----------
resource "aws_iam_role" "lambda" {
  name               = "${var.name}-lambda-upload-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "PutUploadsOnly"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.upload_bucket_name}/uploads/*"]
  }
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.lambda_function_name}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "lambda-s3-put-and-logs"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

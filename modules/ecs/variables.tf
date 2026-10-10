variable "name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids" { type = list(string) }
variable "instance_profile_name" { type = string }
variable "task_execution_role_arn" { type = string }
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "asg_min" {
  type    = number
  default = 2
}
variable "asg_max" {
  type    = number
  default = 3
}
variable "services" {
  description = "Map of service name => HTML body served by that service"
  type        = map(string)
}

variable "name" { type = string }
variable "function_name" { type = string }
variable "bucket_name" { type = string }
variable "lambda_role_arn" { type = string }
variable "source_file" { type = string }
variable "max_upload_bytes" {
  type    = number
  default = 5242880
}

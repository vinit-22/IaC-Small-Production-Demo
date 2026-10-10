variable "name" { type = string }
variable "cidr" { type = string }
variable "azs" { type = list(string) }
variable "public_cidrs" { type = list(string) }
variable "app_cidrs" { type = list(string) }
variable "data_cidrs" { type = list(string) }

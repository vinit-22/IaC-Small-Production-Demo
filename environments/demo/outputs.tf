output "alb_url" { value = "http://${module.ecs.alb_dns_name}" }
output "api_upload_url" { value = "${module.lambda_api.api_url}/upload" }
output "bucket_name" { value = module.lambda_api.bucket_name }
output "lambda_function_name" { value = module.lambda_api.function_name }
output "ecs_cluster" { value = module.ecs.cluster_name }

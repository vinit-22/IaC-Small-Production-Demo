output "api_url" { value = aws_apigatewayv2_api.this.api_endpoint }
output "bucket_name" { value = aws_s3_bucket.uploads.bucket }
output "function_name" { value = aws_lambda_function.upload.function_name }

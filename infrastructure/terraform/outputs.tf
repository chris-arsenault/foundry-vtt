output "foundry_url" {
  description = "Player-facing Foundry URL"
  value       = "https://${local.hostname}"
}

output "instance_id" {
  description = "Game server instance (aws ec2 start-instances / ssm start-session)"
  value       = aws_instance.server.id
}

output "discord_interactions_url" {
  description = "Set as the Interactions Endpoint URL in the Discord application"
  value       = aws_lambda_function_url.discord_wake.function_url
}

output "assets_bucket" {
  description = "Public Foundry media bucket (S3 integration)"
  value       = aws_s3_bucket.assets.id
}

output "releases_bucket" {
  description = "Stage the licensed Foundry release zip here as foundryvtt.zip"
  value       = aws_s3_bucket.releases.id
}

output "efs_id" {
  description = "Foundry data filesystem"
  value       = aws_efs_file_system.data.id
}

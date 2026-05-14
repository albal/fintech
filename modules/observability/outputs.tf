output "documents_bucket_name" {
  value = aws_s3_bucket.documents.id
}

output "audit_log_bucket_name" {
  value = aws_s3_bucket.audit.id
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "transfer_server_id" {
  value = aws_transfer_server.sftp.id
}

output "transfer_server_endpoint" {
  value = aws_transfer_server.sftp.endpoint
}

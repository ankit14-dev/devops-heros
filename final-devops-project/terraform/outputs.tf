output "vpc_id" { value = aws_vpc.main.id }
output "instance_id" { value = aws_instance.k3s.id }
output "public_ip" { value = aws_instance.k3s.public_ip }
output "taskboard_url" { value = "http://${aws_instance.k3s.public_ip}/" }
output "backup_bucket" { value = aws_s3_bucket.backups.bucket }
output "bootstrap_log" { value = "aws ssm start-session --target ${aws_instance.k3s.id}  then: sudo tail -f /var/log/taskboard-bootstrap.log" }

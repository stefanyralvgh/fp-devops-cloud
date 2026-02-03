# SSH KEY PAIR

resource "aws_key_pair" "bastion" {
  key_name   = "${terraform.workspace}-bastion-key"
  public_key = file("${path.module}/keys/movie-analyst-bastion-key.pub")

  tags = {
    Name        = "${terraform.workspace}-bastion-key"
    Environment = terraform.workspace
    ManagedBy   = "Terraform"
  }
}
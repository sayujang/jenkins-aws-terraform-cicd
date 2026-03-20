resource "aws_key_pair" "cicd_kp" {
  key_name   = "cicd_key"
  public_key = file("~/.ssh/testkey.pub")

}
resource "aws_instance" "sonar_inst" {
  ami                    = data.aws_ami.amiID.id
  instance_type          = "c7i-flex.large"
  key_name               = aws_key_pair.cicd_kp.key_name
  vpc_security_group_ids = [aws_security_group.sonarqube_sg.id]
  availability_zone      = var.zone
  tags = {
    Name    = "sonar_instance"
    Project = "cicd"
  }
  provisioner "file" {
    source      = "sonar_setup.sh"
    destination = "/tmp/sonar_setup.sh"
  }
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
  connection {
    type        = "ssh"
    user        = var.user
    private_key = file("~/.ssh/testkey")
    host        = self.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/sonar_setup.sh",
      "sudo /tmp/sonar_setup.sh",
    ]
  }
}
resource "aws_ec2_instance_state" "sonar_state" {
  instance_id = aws_instance.sonar_inst.id
  state       = "running" # or "stopped"
}

resource "aws_instance" "jenkins_inst" {
  ami                    = data.aws_ami.amiID.id
  instance_type          = "c7i-flex.large"
  key_name               = aws_key_pair.cicd_kp.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  availability_zone      = var.zone
  tags = {
    Name    = "jenkins_instance"
    Project = "cicd"
  }
  provisioner "file" {
    source      = "jenkins_setup.sh"
    destination = "/tmp/jenkins_setup.sh"
  }
  connection {
    type        = "ssh"
    user        = var.user
    private_key = file("~/.ssh/testkey")
    host        = self.public_ip
  }
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/jenkins_setup.sh",
      "sudo /tmp/jenkins_setup.sh",
    ]
  }
}
resource "aws_ec2_instance_state" "jenkins_state" {
  instance_id = aws_instance.jenkins_inst.id
  state       = "running" # or "stopped"
}

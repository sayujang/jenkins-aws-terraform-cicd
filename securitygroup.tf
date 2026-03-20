resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins_sg"
  description = "jenkins_sg"

  tags = {
    Name = "jenkins_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_jenkins" {
  security_group_id = aws_security_group.jenkins_sg.id
  cidr_ipv4         = "${chomp(data.http.my_ip.response_body)}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_from_sonarqube" {
  security_group_id            = aws_security_group.jenkins_sg.id
  from_port                    = 8080
  ip_protocol                  = "tcp"
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.sonarqube_sg.id
}
resource "aws_vpc_security_group_ingress_rule" "access_to_web_jenkins" {
  security_group_id = aws_security_group.jenkins_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_jenkins" {
  security_group_id = aws_security_group.jenkins_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6_jenkins" {
  security_group_id = aws_security_group.jenkins_sg.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


resource "aws_security_group" "sonarqube_sg" {
  name        = "sonarqube_sg"
  description = "sonarqube_sg"

  tags = {
    Name = "sonarqube_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_sonarqube" {
  security_group_id = aws_security_group.sonarqube_sg.id
  cidr_ipv4         = "${chomp(data.http.my_ip.response_body)}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_from_jenkins" {
  security_group_id            = aws_security_group.sonarqube_sg.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
  referenced_security_group_id = aws_security_group.jenkins_sg.id
}
resource "aws_vpc_security_group_ingress_rule" "access_to_web_sonar" {
  security_group_id = aws_security_group.sonarqube_sg.id
  cidr_ipv4         = "${chomp(data.http.my_ip.response_body)}/32"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_sonar" {
  security_group_id = aws_security_group.sonarqube_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6_sonar" {
  security_group_id = aws_security_group.sonarqube_sg.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}
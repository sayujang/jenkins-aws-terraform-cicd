variable "region" {
  default = "us-east-1"
}
variable "zone" {
  default = "us-east-1a"
}
variable "lookup" {
  type = map(any)
  default = {
    us-east-1 = "ami-0b6c6ebed2801a5cb"
    us-east-2 = "ami-0198cdf7458a7a932"
  }
}
variable "user" {
  default = "ubuntu"

}
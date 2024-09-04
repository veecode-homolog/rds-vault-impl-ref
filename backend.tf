terraform {
  backend "s3" {
    bucket = "veecode-homolog-terraform-state"
    key    = "rdsvaultimplref/terraform.tfstate"
    region = "us-east-1"
  }
}
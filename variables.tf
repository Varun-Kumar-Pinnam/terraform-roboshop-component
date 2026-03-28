variable "project" {
  type    = string
  default = "roboshop"
}

variable "environment" {
  type    = string
  default = "dev"

}

variable "domain_name" {
  type    = string
  default = "advidevops.online"
}


variable "port_number" {
  type    = number
  default = 8080

}

variable "health_check_path" {
  type    = string
  default = "/health"

}

variable "app_version" {
  default = "v3"
}


# mandatory inputs from child module.
variable "rule_priority" {
  type = number
}

variable "component" {
  type = string
}

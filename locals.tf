locals {

  common_tags = {
    environment = var.environment
    project     = var.project
    terraform   = "true"

  }

  ec2_final_tags = merge(
    {
      Name = "${var.project}-${var.environment}-${var.component}"
    },
    local.common_tags
  )
  ami_id                    = data.aws_ami.main.id
  private_subnet_id         = split(",", data.aws_ssm_parameter.private_subnet_id.value)[0]
  zone_id                   = data.aws_route53_zone.selected.zone_id
  vpc_id                    = data.aws_ssm_parameter.vpc_id.value
  backend_alb_listener_arn  = data.aws_ssm_parameter.backend_alb_listener_arn.value
  frontend_alb_listener_arn = data.aws_ssm_parameter.frontend_alb_listener_arn.value
  alb_listener_arn          = var.component == "frontend" ? local.frontend_alb_listener_arn : local.backend_alb_listener_arn
  health_check_path         = var.component == "frontend" ? "/" : "/health"
  alb_host_header           = var.component == "frontend" ? "${var.component}-${var.environment}.${var.domain_name}" : "${var.component}.backend-alb-${var.environment}.${var.domain_name}"
  port_number               = var.component == "frontend" ? 80 : 443
  sg_id                     = data.aws_ssm_parameter.sg_id.value


}


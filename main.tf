#catalogue instance creation 
resource "aws_instance" "main" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = local.private_subnet_id
  vpc_security_group_ids = [local.sg_id]

  tags = local.ec2_final_tags
}

#terraform_data to provision catalogue 
resource "terraform_data" "main" {
  triggers_replace = aws_instance.main.id

  #connectio block
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.main.private_ip
  }

  #Copy a bootstarp file
  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  #connecting to catalogue server from bastion and configuring with ansile playbook
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment} ${var.app_version}"
    ]
  }
}

#stop the catalogue instance
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on  = [terraform_data.main]
}

#create the AMI with catalogue application in it.
resource "aws_ami_from_instance" "main" {
  name               = "${var.project}-${var.environment}-${var.component}"
  source_instance_id = aws_instance.main.id
  depends_on         = [aws_ec2_instance_state.main]
  tags               = local.ec2_final_tags
}

#Instance Target Group
resource "aws_lb_target_group" "main" {
  name                 = "${var.project}-${var.environment}-${var.component}"
  port                 = local.port_number
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  deregistration_delay = 60

  health_check {
    healthy_threshold   = 2
    interval            = 10
    matcher             = "200-299"
    path                = local.health_check_path
    port                = local.port_number
    protocol            = "HTTP"
    timeout             = 2
    unhealthy_threshold = 3
  }
}

#aws_launch_template
resource "aws_launch_template" "main" {

  name = "${var.project}-${var.environment}-${var.component}"

  image_id = aws_ami_from_instance.main.id

  #once autoscaling sees less traffic, it will terminate the instance
  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.micro"

  #each time we apply terraform this version will be updated as default
  update_default_version = true

  vpc_security_group_ids = [local.sg_id]

  #tags for instances created by launch template through autoscaling
  tag_specifications {
    resource_type = "instance"
    tags          = local.ec2_final_tags
  }

  # tags for volumes created by instances
  tag_specifications {
    resource_type = "volume"
    tags          = local.ec2_final_tags
  }

  # tags for launch template
  tags = local.ec2_final_tags
}

resource "aws_autoscaling_group" "main" {
  name                      = "${var.project}-${var.environment}-${var.component}"
  max_size                  = 10
  min_size                  = 1
  health_check_grace_period = 120
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = false
  vpc_zone_identifier       = [local.private_subnet_id]
  target_group_arns         = [aws_lb_target_group.main.arn]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  #if there is any change in launch template, instance refresh will be triggered and new instances will be created
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  #dynamic block for tags
  dynamic "tag" {
    for_each = local.ec2_final_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  #within 15min autoscaling should be completed , otherwise it will stop and delete the instances.
  timeouts {
    delete = "15m"
  }

}

resource "aws_autoscaling_policy" "main" {
  name                      = "${var.project}-${var.environment}-${var.component}"
  autoscaling_group_name    = aws_autoscaling_group.main.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 120

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 70.0
  }
}

# This depends on target group
resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn
  priority     = var.rule_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
  condition {
    host_header {
      values = [local.alb_host_header]
    }
  }
}

#terraform_data to delete catalogue 
resource "terraform_data" "main_delete" {
  triggers_replace = aws_instance.main.id

  depends_on = [aws_autoscaling_policy.main]

  #it executes from bastion
  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
} 
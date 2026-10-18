# El NLB es interno, multi-AZ y tiene un listener y un grupo de destinos por servicio expuesto.

mock_provider "aws" {}

variables {
  name                    = "solventa-staging"
  vpc_id                  = "vpc-0123456789abcdef0"
  vpc_cidr                = "10.40.0.0/16"
  subnet_ids              = ["subnet-a", "subnet-b"]
  node_security_group_id  = "sg-0123456789abcdef0"
  autoscaling_group_names = { default = "asg-default" }
  services = {
    "solventa-backend"   = { node_port = 30080 }
    "solventa-identidad" = { node_port = 30081 }
  }
  tags = { Project = "solventa" }
}

run "internal_multi_az_network_balancer" {
  command = plan

  assert {
    condition     = aws_lb.this.internal && aws_lb.this.load_balancer_type == "network"
    error_message = "RULE nlb-internal: the NLB must be internal and of type network (layer 4)."
  }

  assert {
    condition     = aws_lb.this.enable_cross_zone_load_balancing
    error_message = "RULE nlb-multi-az: cross-zone load balancing must be enabled."
  }

  assert {
    condition     = length(aws_lb.this.subnets) == 2
    error_message = "RULE nlb-multi-az: the NLB must span the private subnets of every AZ."
  }
}

run "one_listener_target_group_and_node_port_rule_per_service" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.this) == 2 && length(aws_lb_target_group.this) == 2
    error_message = "RULE per-service: each exposed service needs its own listener and target group."
  }

  assert {
    condition     = aws_lb_listener.this["solventa-backend"].port == 30080 && aws_lb_target_group.this["solventa-backend"].port == 30080
    error_message = "RULE node-port: the listener and the target group must use the service NodePort."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.node_port : r.cidr_ipv4 == "10.40.0.0/16"])
    error_message = "RULE node-port-source: NodePorts must only be reachable from the VPC."
  }

  assert {
    condition     = length(aws_autoscaling_attachment.this) == 2
    error_message = "RULE targets: every node group must be attached to every target group."
  }
}

run "fewer_than_two_subnets_fails" {
  command = plan

  variables {
    subnet_ids = ["subnet-a"]
  }

  expect_failures = [var.subnet_ids]
}

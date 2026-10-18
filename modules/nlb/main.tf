# Network Load Balancer interno (capa 4) que expone cada microservicio hacia el API Gateway dentro de la VPC.
# Lo crea Terraform y no un controlador de Kubernetes: el destroy no deja balanceadores huérfanos (research R11).
# Propiedad operativa: el idle timeout TCP del NLB es fijo en 350 s y no es configurable.

locals {
  # Las claves son estáticas (servicio y node group); el nombre del ASG solo se conoce al aplicar.
  attachments = {
    for pair in setproduct(keys(var.services), keys(var.autoscaling_group_names)) :
    "${pair[0]}/${pair[1]}" => { service = pair[0], asg = var.autoscaling_group_names[pair[1]] }
  }
}

resource "aws_lb" "this" {
  name               = substr("${var.name}-nlb", 0, 32)
  load_balancer_type = "network"
  internal           = true
  subnets            = var.subnet_ids

  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  for_each = var.services

  name        = substr("${var.name}-${each.key}", 0, 32)
  port        = each.value.node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.tags, { Service = each.key })
}

resource "aws_lb_listener" "this" {
  for_each = var.services

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.node_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  tags = var.tags
}

# Los nodos del grupo de autoescalado se registran solos en el grupo de destinos, también al escalar.
resource "aws_autoscaling_attachment" "this" {
  for_each = local.attachments

  autoscaling_group_name = each.value.asg
  lb_target_group_arn    = aws_lb_target_group.this[each.value.service].arn
}

# El NLB conserva la IP de origen con destinos de tipo instance: llega con una IP de la VPC.
resource "aws_vpc_security_group_ingress_rule" "node_port" {
  for_each = var.services

  security_group_id = var.node_security_group_id
  description       = "NodePort de ${each.key} desde la VPC (NLB y health checks)"
  ip_protocol       = "tcp"
  from_port         = each.value.node_port
  to_port           = each.value.node_port
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

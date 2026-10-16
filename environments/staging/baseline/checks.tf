# Edge case "imagen inexistente": el apply falla antes de crear o cambiar cualquier carga.

data "aws_ecr_images" "service" {
  for_each = var.check_images_exist ? local.services : {}

  repository_name = each.key
}

resource "terraform_data" "image_check" {
  for_each = var.check_images_exist ? local.services : {}

  lifecycle {
    precondition {
      condition     = contains([for i in data.aws_ecr_images.service[each.key].image_ids : i.image_tag], each.value.image_tag)
      error_message = "Image ${each.key}:${each.value.image_tag} not found. Push it first (README §\"Publicar la primera imagen\")."
    }
  }
}

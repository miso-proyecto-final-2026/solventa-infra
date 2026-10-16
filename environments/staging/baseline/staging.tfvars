# Valores de staging para la etapa baseline.
region             = "us-east-1"
check_images_exist = true

# El bucket se pasa con -var state_bucket=... o TF_VAR_state_bucket (salida state_bucket del bootstrap).
# Para fijar el SHA en ejecución sin editar services.yaml:
# image_tags = { solventa-backend = "<sha>" }

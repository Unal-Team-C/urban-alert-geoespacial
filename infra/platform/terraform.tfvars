region = "us-east-2"
name   = "urban-alert-geoespacial"

db_name                     = "geospatial"
db_app_user                 = "geospatial_app"
db_engine_version           = "17"
db_instance_class           = "db.t4g.micro"
db_allocated_storage_gb     = 20
db_max_allocated_storage_gb = 50
db_backup_retention_days    = 7

ecr_keep_images    = 20
log_retention_days = 30

schema_task_cpu    = 256
schema_task_memory = 512

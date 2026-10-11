region       = "us-east-2"
state_bucket = "urban-alert-tfstate-348364742283"

cpu               = "512"
memory            = "1024"
container_port    = 8000
health_check_path = "/health"

min_tasks          = 1
max_tasks          = 10
cpu_target_percent = 60

db_pool_min  = 1
db_pool_max  = 5
max_radius_m = 6000

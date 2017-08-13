# Gems
require 'aws-sdk'
require 'pry-byebug'

ecs = Aws::ECS::Client.new()

def transform_to_validate_task(task)
    task_as_hash = task.to_h
    task_as_hash.delete(:revision)
    task_as_hash.delete(:status)
    task_as_hash.delete(:task_definition_arn)
    task_as_hash.delete(:requires_attributes)
    task_as_hash
end

cluster = ARGV[0]
service = ARGV[1]
image_tag = ARGV[2]
time_to_wait = ARGV[3].to_i

# Use as env variables
credentials = { AWS_REGION: 'eu-central-1',
                AWS_ACCESS_KEY_ID: 'AKIAJXIQ3F4OPH4QLFCA',
                AWS_SECRET_ACCESS_KEY: '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'
            }

response = ecs.describe_services({cluster: cluster, services:  [service] })
first_active_task = response.services.first.deployments.select{|d| d.status == "ACTIVE"}.first

if first_active_task.nil?
    primary_task_ARN = response.services.first.deployments.select{|d| d.status == "PRIMARY"}.first.task_definition
else
    primary_task_ARN = first_active_task.task_definition
end

# primary_task_ARN = response.services.first.task_definition



# update containers images. all images will be having the same tag
response = ecs.describe_task_definition(task_definition: primary_task_ARN)
task_definition = response.task_definition
image = task_definition.container_definitions.first.image
current_tag = image.split(':').last

# Create a new task definition with a different tag for all images
NEW_container_definitions = task_definition.container_definitions.each do |container_df|
    container_df.image = container_df.image.gsub(/#{current_tag}$/, image_tag)
end

task_definition.container_definitions = NEW_container_definitions
NEW_task_definition = task_definition

valid_task = transform_to_validate_task(NEW_task_definition)

# Register the new task definition
response = ecs.register_task_definition(valid_task)
desired_task_ARN = response.task_definition.task_definition_arn

# Update services
ecs.update_service({cluster: cluster, service: service, task_definition: desired_task_ARN})

count = 0
wait_seconds = 2 # 2 seconds
deployment_success = false


while(count < time_to_wait) do
    response = ecs.describe_services(cluster: cluster, services: [service])
    running_service = response.services.first
    if running_service.desired_count > 0
        sleep(wait_seconds)
        count = count + wait_seconds
        print "."
    elsif desired_count == 0
        deployment_success = true
        puts "Deployment success"
        break
    end
end

unless deployment_success
    # rollback
    puts "\n Rolling back..."
    ecs.update_service({cluster: cluster, service: service, task_definition: primary_task_ARN })
    response = ecs.describe_services(services: [service])
    raise "Deployment failed #{ response.failures }"
end

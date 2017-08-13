# Gems
require 'aws-sdk'
require 'pry-byebug'

class EcsTaskDeploy
    def initialize(args)
        @ecs_client           = Aws::ECS::Client.new()
        @cluster              = args[0]
        @service              = args[1]
        @desired_image_tag    = args[2]||latest
        @time_to_wait         = args[3].to_i||600
        @primary_task_ARN     = nil
        @desired_task_ARN     = nil
    end


    def transform_to_validate_task(task)
        task_as_hash = task.to_h
        task_as_hash.delete(:revision)
        task_as_hash.delete(:status)
        task_as_hash.delete(:task_definition_arn)
        task_as_hash.delete(:requires_attributes)
        task_as_hash
    end

    def start_deployment
        response = @ecs_client.describe_services({cluster: @cluster, services:  [@service] })
        first_active_task = response.services.first.deployments.select{|d| d.status == "ACTIVE"}.first

        # @primary_task_ARN = response.services.first.task_definition(ecs-deploy bash script)
        if first_active_task.nil?
            @primary_task_ARN = response.services.first.deployments.select{|d| d.status == "PRIMARY"}.first.task_definition
        else
            @primary_task_ARN = first_active_task.task_definition
        end

        # update containers images. all images will be having the same tag
        response = @ecs_client.describe_task_definition(task_definition: @primary_task_ARN)
        task_definition = response.task_definition
        image = task_definition.container_definitions.first.image
        current_tag = image.split(':').last

        # Create a new task definition with a different tag for all images
        new_container_definitions = task_definition.container_definitions.each do |container_df|
            container_df.image = container_df.image.gsub(/#{current_tag}$/, @desired_image_tag)
        end

        task_definition.container_definitions = new_container_definitions
        new_task_definition = task_definition

        valid_task = transform_to_validate_task(new_task_definition)

        # Register the new task definition
        response = @ecs_client.register_task_definition(valid_task)
        @desired_task_ARN = response.task_definition.task_definition_arn

        # Update services
        @ecs_client.update_service({cluster: @cluster, service: @service, task_definition: @desired_task_ARN})

        count = 0
        wait_seconds = 2 # 2 seconds
        deployment_success = false

        while(count < @time_to_wait) do
            response = @ecs_client.describe_services(cluster: @cluster, services: [@service])
            running_service = response.services.first
            if running_service.deployments.count
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
            @ecs_client.update_service({cluster: @cluster, service: @service, task_definition: @primary_task_ARN })
            response = @ecs_client.describe_services(services: [@service])
            raise "Deployment failed #{ response.failures }"
        end
    end
end

EcsTaskDeploy.new(ARGV).start_deployment

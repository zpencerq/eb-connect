require 'eb-connect/version'
require 'aws-sdk'

module ElasticBeanstalk
  class Driver
    def ask?(question, options)
      answer = nil
      answer = options[0] if options.length == 1

      while answer == nil
        puts "",question
        options
          .each.with_index(1) do |option, idx|
          puts "[#{idx}] #{option[:name]}"
        end
        print "Choose: "
        input = gets.chomp.to_i
        begin
          answer = options[input-1]
        rescue
          puts "Invalid choice, please try again.\n"
        end
      end
      answer
    end

    def connect
      begin
        user = Aws::STS::Client.new.get_caller_identity
      rescue Aws::Errors::MissingCredentialsError
        puts "Uh oh. AWS Credentials could not be found!", ""
        puts "Do one of the following, then try eb-connect again:"
        puts " * Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to ENV"
        puts " * Setup ~/.aws/credentials file"
        return
      rescue Errno::EHOSTDOWN
        puts "AWS API is not responding, please wait and try again."
        puts "You may be rate-limited."
        return
      end

      puts "Welcome to EB-Connect!"

      client = Aws::ElasticBeanstalk::Client.new
      applications = client.describe_applications[:applications].map do |app|
        {application_name: app[:application_name], name: app[:application_name]}
      end.sort_by { |option| option[:name] }

      application = ask?("Applications", applications)
      environments = client.describe_environments(application_name: application[:application_name])[:environments].map do |environment|
        {
          environment_name: environment[:environment_name],
          environment_id: environment[:environment_id],
          name: environment[:environment_name]
        }
      end.sort_by { |option| option[:name] }

      environment = ask?("Environments", environments)
      instances = Aws::EC2::Client.new.describe_instances(
        instance_ids: client.describe_environment_resources(
          environment_id: environment[:environment_id],
          environment_name: environment[:environment_name],
        )[:environment_resources][:instances].map(&:id)
      ).flat_map(&:reservations).flat_map(&:instances)
        .select do |instance|
        instance.state.name == "running"
      end
        .each_with_index.map do |instance, idx|
        name_tag = instance.tags.select do |tag| tag.key == "Name" end.first
        ip = instance[:public_ip_address] ? instance[:public_ip_address] : instance[:private_ip_address]

        {
          instance_id: instance[:instance_id],
          name: "#{name_tag ? name_tag.value : ""} (#{ip})",
          ip: ip,
        }
      end.sort_by { |option| option[:name] }

      instance = ask?("Instances", instances)

      ssh_cmd = "ssh #{instance[:ip]}"
      puts "", ssh_cmd
      exec ssh_cmd
    end
  end
end

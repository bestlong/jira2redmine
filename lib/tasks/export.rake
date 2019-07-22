require './lib/jira/exporter'
require './lib/redmine/connector'

task :export do
	options = {
		:JIRA_XML => Dir.getwd,
		:JIRA_FILES => Dir.getwd,
		:REDMINE_URL => nil,
		:REDMINE_KEY => nil,
	}

	ENV.each do |n, v|
		if options.key?(n.to_sym)
			options[n.to_sym] = v.to_s.gsub(/\s+/, "")
		end
	end

	if (options[:REDMINE_URL] == nil)
		raise "Invalid REDMINE API url!"
	end

	if (options[:REDMINE_KEY] == nil)
		raise "Invalid REDMINE API key!"
	end

	Redmine = Connector.new({:url => options[:REDMINE_URL], :key => options[:REDMINE_KEY]})
	Redmine.execute(:users)

	#Exporter.new(options[:JIRA_XML]).migrate
end

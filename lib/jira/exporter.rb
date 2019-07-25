require 'nokogiri'
require 'digest'
require 'fileutils'
require 'active_record'

require './lib/jira/builder'

namespace :jira do
	class ExtendedStruct < Struct
		def initialize(params = {})
			params.each do |k,v|
				if self.members.include?(k.to_sym)
					send("#{k}=", v)
				end
			end
		end
	end

	JiraProject = ExtendedStruct.new(:name, :lead, :description, :key)
	JiraIssue = ExtendedStruct.new(:key, :project, :creator, :assignee, :type, :summary, :description, :priority, :status, :created, :updated)
	JiraComment = ExtendedStruct.new(:issue, :author, :body, :created)
	JiraAttache = ExtendedStruct.new(:issue, :author, :mimetype, :filename, :created, :filesize)
	JiraHistory = ExtendedStruct.new(:group, :fieldtype, :field, :newvalue, :newstring)
	JiraHistoryGroup = ExtendedStruct.new(:issue, :author, :created)

	class Exporter
		JIRA_ENTITIES_FILE = 'entities.xml'
		JIRA_ATTACHMENTS_FOLDER = 'attachments'

		def initialize(xmlPath, connector, output)
			raise "Argument error blah blah" unless connector.kind_of?(Connector)

			@xml = Nokogiri::XML(File.new(xmlPath + "/" + JIRA_ENTITIES_FILE, 'r:utf-8'),nil,'utf-8'){ |c| c.noblanks }

			if @xml.root.children.count < 1
				raise "Source XML is empty!"
			end

			@files = File.join(xmlPath, JIRA_ATTACHMENTS_FOLDER)
			if !Dir.exist? @files
				raise "Invalid attachments directory: %s"  % @files
			end

			@output = output
			if !Dir.exist? @output
				raise "Invalid output directory: %s"  % @output
			end


			load_jira_statuses
			load_jira_users
			load_jira_types
			load_jira_priorities
			load_jira_projects
			load_jira_issues

			load_jira_comments
			load_jira_history
			load_jira_attaches

			@connector = connector
			@builder = Builder.new(@output)
		end

		def migrate
			puts "Prepare roles..."
			prepare_roles

			puts "Prepare statuses..."
			if prepare_statuses < 1

				puts "Prepare trackers..."
				if prepare_trackers < 1

					puts "Prepare priorities..."
					if prepare_priorities < 1

						puts "Migrate users..."
						migrate_users

						puts "Migrate projects..."
						migrate_projects

						puts "Migrate issues..."
						migrate_issues
					else
						puts "[Error] Sorry! Undefined priorities found!"
					end
				else
					puts "[Error] Sorry! Undefined trackers found!"
				end
			else
				puts "[Error] Sorry! Undefined statuses found!"
			end

			puts "Finished"
		end

		@@default_role_name = "developer"
		def prepare_roles
			@default_role = @connector.roles.select{|v|
				v[:name].downcase == @@default_role_name}.first

			if @default_role == nil
				raise "No default role found!"
			end
		end

		@@statuses_aliases = {
			"open" => "new",
			"to do" => "new",
			"done" => "resolved",
			"review" => "resolved",
			"rework" => "reworking",
			"reopened" => "reworking"
		}
		def prepare_statuses
			@statuses_binding = {}

			redmine_statuses = @connector.statuses
			count = 0

			@statuses.each do |id, name|
				puts "[JIRA] Status found: %s" % name

				search = name.downcase
				if @@statuses_aliases.key?(search)
					search = @@statuses_aliases[search]
				end

				redmine_status = redmine_statuses.select{|v| v[:name].downcase == search}.first
				if (redmine_status != nil)
					puts "[Redmine API] Status assigned: %s!" % redmine_status[:name]
					@statuses_binding[id] = redmine_status[:id]
				else
					puts "[Redmine API] Undefined status: %s" % name
					count += 1
				end
			end

			# @statuses_binding.each {|k, v| p "%s: %s" % [k, v]}

			return count
		end

		@@trackers_aliases = {
			"epic" => "feature",
			"story" => "feature",
			"task" => "feature",
			"sub-task" => "support",
		}
		def prepare_trackers
			@trackers_binding = {}

			redmine_trackers = @connector.trackers
			count = 0

			@types.each do |id, name|
				puts "[JIRA] Tracker found: %s" % name

				search = name.downcase
				if @@trackers_aliases.key?(search)
					search = @@trackers_aliases[search]
				end

				redmine_tracker = redmine_trackers.select{|v| v[:name].downcase == search}.first
				if (redmine_tracker != nil)
					puts "[Redmine API] Tracker assigned: %s!" % redmine_tracker[:name]
					@trackers_binding[id] = redmine_tracker[:id]
				else
					puts "[Redmine API] Undefined tracker: %s" % name
					count += 1
				end
			end

			# @trackers_binding.each {|k, v| p "%s: %s" % [k, v]}
			return count
		end

		@@priorities_aliases = {
			"lowest" => "low",
			"highest" => "urgent",
			"medium" => "normal",
		}
		def prepare_priorities
			@priorities_binding = {}

			redmine_priorities = @connector.priorities
			count = 0

			@priorities.each do |id, name|
				puts "[JIRA] Priority found: %s" % name

				search = name.downcase
				if @@priorities_aliases.key?(search)
					search = @@priorities_aliases[search]
				end

				redmine_priority = redmine_priorities.select{|v| v[:name].downcase == search}.first
				if (redmine_priority != nil)
					puts "[Redmine API] Priority assigned: %s!" % redmine_priority[:name]
					@priorities_binding[id] = redmine_priority[:id]
				else
					puts "[Redmine API] Undefined priority: %s" % name
					count += 1
				end
			end

			# @priorities_binding.each {|k, v| p "%s: %s" % [k, v]}
			return count
		end

		def migrate_users
			@user_binding = {}
			redmine_users = @connector.users

			@users.each do |id, info|
				puts "[JIRA] Found user: %s" % info[:mail]

				redmine_user = redmine_users.select{|v| v[:mail] == info[:mail] }.first
				if redmine_user != nil
					puts "[Redmine API] User already exists: %s" % redmine_user[:mail]
				else
					redmine_user = @connector.create_user info

					if redmine_user == nil
						raise "[Error] Can't create user: %s" % email
					end

					puts "[Redmine API] Created user: %s" % redmine_user[:mail]
				end

				@user_binding[id] = redmine_user[:id]
			end

			# @user_binding.each {|k, v| p "%s: %s" % [k, v]}
		end

		def migrate_projects
			@projects_binding = {}
			redmine_projects = @connector.projects

			@projects.each do |id, info|
				puts "[JIRA] Found project: %s" % info.key

				redmine_project = redmine_projects.select{|v| v[:identifier] == info.key.downcase }.first
				if redmine_project != nil
					puts "[Redmine API] User already exists: %s" % redmine_project[:identifier]
				else
					redmine_project = @connector.create_project info.to_h

					if redmine_project == nil
						raise "[Error] Can't create project: %s" % info.key
					end

					puts "[Redmine API] Created project: %s" % redmine_project[:identifier]
				end

				@projects_binding[id] = redmine_project[:id]
			end

			# @projects_binding.each {|k, v| p "%s: %s" % [k, v]}
		end

		def migrate_issues
			@issues_binding = {}

			@issues.each do |id, info|
				puts "[JIRA] Found issue: %s" % info.key

				# issue_project = @projects.select {|_, v| v.key = info.key }
				# comments = @comments.select {|_k, v| v.issue == id }
				# if comments.length < 1
				# 	next
				# end

				# attaches = @attaches.select {|_k, v| v.issue == id }
				# if attaches.length < 1
				# 	next
				# end

				data = {
					:project_id => @projects_binding[info.project],
					:tracker_id => @trackers_binding[info.type],
					:priority_id => @priorities_binding[info.priority],
					:subject => info.summary,
					:description => info.description
				}

				redmine_issue = @connector.create_issue data
				if redmine_issue == nil
					raise "[Error] Can't create issue: %s" % info.key
				end

				@builder.update_issue(redmine_issue[:id], {
					:status_id => @statuses_binding[info.status],
					:created => info.created,
					:updated => info.updated,
				})

				attaches = @attaches.select {|_k, v| v.issue == id }
				if attaches.length > 0
					attaches.each do |aid, ainfo|
						attachment_file = File.join(@files,@projects[info.project].key, "10000", info.key, aid, )
						if !File.exist? attachment_file
							raise "Attachment file is not exists: %s!" % attachment_file
						end

						if !File.readable? attachment_file
							raise "Attachment file is not readable: %s!" % attachment_file
						end

						filename = "%s_%s" % [id, ainfo[:filename]]
						destination = File.join(@output, "jira", filename)

						FileUtils.mkdir_p(File.dirname(destination))
						FileUtils.cp(attachment_file, destination)

						sha256 = Digest::SHA256.new
						File.open(destination, 'rb') do |f|
							while buffer = f.read(8192)
								sha256.update(buffer)
							end
						end

						attache_user = @user_binding[(@users.select {|_k, u| u[:login] == ainfo[:author]}.first)[0]]
						@builder.create_history_event_attachments(redmine_issue[:id], {
							:name => ainfo[:filename],
							:user_id => attache_user,
							:filename => filename,
							:created => ainfo[:created],
							:filesize => ainfo[:filesize],
							:digest => sha256.hexdigest,
							:type => ainfo[:mimetype],
						})
					end
				end

				groups = @history_groups.select {|_k, v| v[:issue] == id }
				if groups.length > 0
					groups.each do |gid, ginfo|

						events = @history.select {|_k, v| v[:group] == gid}
						if events.length > 0

							old_status = @statuses.key("Open")
							if old_status == nil
								raise "Invalid default status!"
							end

							events.each do |_, einfo|
								if einfo[:field] == "status"
									value = @statuses_binding[einfo[:newvalue]]
									event_user = @user_binding[(@users.select {|_k, u| u[:login] == ginfo[:author]}.first)[0]]

									@builder.create_history_event_status(redmine_issue[:id], {
										:journal_id => redmine_issue[:id],
										:user_id => event_user,
										:old_value => old_status,
										:value =>  value,
										:created => ginfo[:created],
									})

									old_status = value
								end
							end
						end
					end
				end

				if info.assignee != nil
					@users.each do |k, u|
						if u[:login] == info.assignee

							membership = @connector.memberships data[:project_id]
							if !membership.include? @user_binding[k]
								@connector.create_membership(@projects_binding[info.project], {
									:user_id => @user_binding[k],
									:role_ids => [@default_role[:id]]
								})
							end

							@connector.update_issue redmine_issue[:id], {:assigned_to_id => @user_binding[k]}
							puts "[Redmine API] Issue assigned to %s" % info.assignee
						end
					end
				end

				# if comments.length > 0
				# 	comments.each do |c|
				# 		@connector.update({:notes => []})
				# 	end
				# end

				puts "[Redmine API] Created issue: %s" % info.summary
				@issues_binding[id] = redmine_issue[:id]
			end

			@projects_binding.each {|k, v| p "%s: %s" % [k, v]}
		end

		def load_jira_statuses
			@statuses = {}

			get_list_from_tag('/*/Status', :name, :id).each do |v|
				@statuses[v['id']] = v['name']
			end
		end

		def load_jira_users
			@users = {}

			get_list_from_tag('/*/User', :id, :userName, :emailAddress, :firstName, :lastName, ).each do |v|
				@users[v['id']] = {:login => v['userName'],
								   :mail => v['emailAddress'], :firstname => v['firstName'], :lastname => v['lastName']}
			end
		end

		def load_jira_types
			@types = {}

			get_list_from_tag('/*/IssueType', :name, :id).each do |v|
				@types[v['id']] = v['name']
			end
		end

		def load_jira_priorities
			@priorities = {}

			get_list_from_tag('/*/Priority', :name, :id).each do |v|
				@priorities[v['id']] = v['name']
			end
		end

		def load_jira_projects
			@projects = {}

			get_list_from_tag('/*/Project', :id, :name, :key, :lead, :description).each do |v|
				@projects[v['id']] = JiraProject.new(v)
			end
		end

		def load_jira_issues
			@issues = {}
			get_list_from_tag('/*/Issue', :id, :key, :project, :creator, :assignee, :type,
				:summary, :description, :priority, :status, :created, :updated).each do |v|
					@issues[v['id']] = JiraIssue.new(v)
			end
		end

		def load_jira_comments
			@comments = {}
			get_list_from_tag('/*/Action[@type="comment"]', :id, :issue, :author, :body, :created).each do |v|
				if v['body'].to_s.length > 0
					@comments[v['id']] = JiraComment.new(v)
				end
			end
		end


		def load_jira_attaches
			@attaches = {}
			get_list_from_tag('/*/FileAttachment',:id, :issue, :author, :mimetype, :filename, :created, :filesize).each do |v|
				@attaches[v['id']] = JiraAttache.new(v)
			end
		end

		@@history_types = %w(status timespent timeestimate attachment)
		def load_jira_history
			@history_groups = {}
			get_list_from_tag('/*/ChangeGroup', :id, :issue, :author, :created).each do |v|
				@history_groups[v['id']] = JiraHistoryGroup.new(v)
			end

			@history = {}
			get_list_from_tag('/*/ChangeItem', :id, :group, :fieldtype, :field, :newvalue, :newstring).each do |v|
				@history[v['id']] = JiraHistory.new(v)
			end

			@history = @history.select {|_k, v| v[:fieldtype] == "jira" && @@history_types.include?(v[:field].downcase)}
		end


		def get_list_from_tag(query, *attributes)
			ret = []

			@xml.xpath(query).each {|node|
				ret.push(Hash[node.attributes.select() { |k, _v|
					attributes.empty? || attributes.include?(k.to_sym)}.map { |k,v| [k,v.content]}])}

			return ret
		end

		private :get_list_from_tag, :load_jira_types, :load_jira_priorities,
			:load_jira_statuses, :load_jira_projects, :load_jira_issues, :load_jira_comments
	end
end
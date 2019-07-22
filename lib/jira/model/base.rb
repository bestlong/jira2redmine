namespace :jira do
	namespace :model do

		class Base

			MAP = {}

			attr_reader :tag
			attr_accessor :new_record, :is_new

			def map
				self.class::MAP
			end

			def initialize(node)
				@tag = node
			end

			def method_missing(key, *args)
				if key.to_s.start_with?('jira_')
					attr = key.to_s.sub('jira_', '')
					return @tag[attr]
				end
				puts "Method missing: #{key}"
				raise NoMethodError key
			end

			def run_all_redmine_fields
				ret = {}
				self.methods.each do |method_name|
					m = method_name.to_s
					if m.start_with?('red_')
						mm = m.to_s.sub('red_', '')
						ret[mm] = self.send(m)
					end
				end
				return ret
			end

			def migrate
				all_fields = self.run_all_redmine_fields()
				#pp('Saving:', all_fields)
				record = self.retrieve
				if record
					record.update_attributes(all_fields)
				else
					record = self.class::DEST_MODEL.new all_fields
					self.is_new = true
				end
				if self.respond_to?('before_save')
					self.before_save(record)
				end

				record.save!
				record.reload
				self.map[self.jira_id] = record
				self.new_record = record
				if self.respond_to?('post_migrate')
					self.post_migrate(record, self.is_new)
				end
				record.reload
				return record
			end

			def retrieve
				self.class::DEST_MODEL.find_by_name(self.jira_id)
			end
		end
	end
end
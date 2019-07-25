namespace :jira do
	class Builder

		def initialize(path)
			@file = path + "/migrate.sql"
		end

		def store(string)
			File.write(@file, string + "\n", mode: 'a')
		end

		def update_issue(id, data)
			store("UPDATE `issues` SET `created_on` = TIMESTAMP('%s'), start_date=TIMESTAMP('%s'), updated_on = TIMESTAMP('%s'), `status_id` = %s WHERE id = %s;" % [data[:created], data[:created], data[:updated], data[:status_id], id]);
			store("UPDATE `journals` set `created_on` = TIMESTAMP('%s') WHERE `journalized_type`='Issue' AND `journalized_id`='%s';" % [data[:created], id])
		end

		def create_history_event_status(id, data)
			store("INSERT INTO `journals` (`journalized_id`, `journalized_type`, `user_id`, `notes`, `created_on`) VALUES (%s, 'Issue', %s, '', TIMESTAMP('%s'));" % [id, data[:user_id], data[:created]])
			store("INSERT INTO `journal_details` (`journal_id`, `property`, `prop_key`, `old_value`, `value`) VALUES (LAST_INSERT_ID(), 'attr', 'status_id', '%s', '%s');" % [data[:old_value], data[:value]]);
		end

		def create_history_event_attachments(id, data)
			store("INSERT INTO `attachments` (`container_id`, `description`, `author_id`, `container_type`, `filename`, `disk_filename`, `disk_directory`, `filesize`, `content_type`, `digest`, `created_on`) VALUES (%s, '', %s, 'Issue', '%s', '%s', 'jira', '%s', '%s', '%s', TIMESTAMP('%s'));" % [id, data[:user_id], data[:name], data[:filename], data[:filesize], data[:type], data[:digest], data[:created]])
			store("SELECT LAST_INSERT_ID() INTO @PROP_KEY;")
			store("INSERT INTO `journals` (`journalized_id`, `journalized_type`, `user_id`, `notes`, `created_on`) VALUES (%s, 'Issue', %s, '', TIMESTAMP('%s'));" % [id, data[:user_id], data[:created]])
			store("INSERT INTO `journal_details` (`journal_id`, `property`, `prop_key`, `value`) VALUES (LAST_INSERT_ID(), 'attachment', @PROP_KEY, '%s');" % [data[:name]]);
		end

		def create_history_event_comment(id, data)
			store("INSERT INTO `journals` (`journalized_id`, `journalized_type`, `user_id`, `notes`, `created_on`) VALUES (%s, 'Issue', %s, FROM_BASE64('%s'), TIMESTAMP('%s'));" % [id, data[:user_id], data[:body], data[:created]])
		end

		private :store
	end
end
# Introduction
The easiest way to migrate data from JIRA v8.1 into redmine 4.0.4.

## Supported

- Users
- Project:
- Project members role
- Issues
- Issues history

## Not supported

- Custom fields
- Workflow

## Environment

### Software
* [JIRA] v 8.1
* [redmine] v 4.0.4
* [MariaDB] v 10.4.6

### Variables

`JIRA_XML=` path to entities.xml (exported from JIRA)  
`REDMINE_URL=` the Remine location (fresh install only)  
`REDMINE_KEY=` the Redmine API secret key  
`SQL_OUTPUT=` the output directory  (has to be writable)

## How to

```shell
cp .env.example .env
```

```shell
rake export
```

Don't forget to set the environment variables before!

## Notes

The Redmine API will be used as far as possible.

The attachments file will be stored into the output directory - just copy in into `./redmine/files/` folder.

The `mirgation.sql` script has to be used on the Redmine database to finish the migration.

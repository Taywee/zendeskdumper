# This is simply here in case we want any of this data available from within the
# running library, especially for generating the useable command line
module ZenDeskDumper
  module Meta
    NAME = 'zendeskdumper'
    VERSION = '0.1.0'
    DATE = '2018-01-02'
    SUMMARY = 'A simple dumper for a ZenDesk domain.'
    DESCRIPTION = 'A simple dumper for a ZenDesk domain.  Attempts to pull all users, tickets, comments, and attachments'
    AUTHORS = ['Taylor C. Richberger']
    EMAIL = 'tcr@absolute-performance.com'
    FILES = [
      'bin/zendeskdumper',
      'lib/zendeskdumper.rb',
      'lib/zendeskdumper/meta.rb',
    ]
    HOMEPAGE = 'https://rubygems.org/gem/zendeskdumper'
    LICENSE = 'MIT'
  end
end

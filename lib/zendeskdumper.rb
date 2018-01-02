require 'json'
require 'net/http'
require 'pathname'

module ZenDeskDumper
  # A special dumper class.  The "dump" method will use a passed-in block to
  # generate, that way it can actually be used to directly write into an archive
  # or something of the sort if desired.  All path names are kept relative
  class Dumper
    attr_accessor :domain, :username, :password

    def initialize(domain:, username:, password:)
      @logger = Logger.new(STDERR)

      @domain = domain
      @username = username
      @password = password

      @threadlimit = 50
    end

    # Main method to call for this type; runs the full dumper.  Uses a passed-in
    # block to generate all files.
    def dump(&block)
      @logger.info 'pulling users'
      dump_users(&block)
      @logger.info 'pulling organizations'
      dump_organizations(&block)
      @logger.info 'pulling tickets'
      dump_tickets(&block)
    end

    # Run a list of items, yield to the block, and join on the thread limit (and
    # before finishing
    def checkthreads(list)
      threads = []
      list.each do |item|
        threads << Thread.new do
          yield item
        end
        if threads.size >= @threadlimit
          threads.each(&:join)
          threads = []
        end
      end
      threads.each(&:join)
    end

    # Get method which runs requests and optionally sleeps if necessary based on
    # ratelimiting
    def get(uri)
      request = Net::HTTP::Get.new uri
      request.basic_auth(@username, @password)
      response = Net::HTTP::start(uri.host, uri.port, use_ssl: true) do |http|
        http.request request
      end
      if Integer(response.code) == 429
        # Make sure to allow some decent grace period
        time = Integer(response['Retry-After']) + 60
        @logger.debug "Hitting rate limiting, sleeping for #{time} seconds"
        sleep time
        return get uri
      end
      # Raise errors when necessary
      response.value
      response
    end

    # Get an attachment file, following redirects, and return its body
    def get_attachment(uri, limit=10)
      raise ArgumentError, 'too many redirects' if limit == 0

      request = Net::HTTP::Get.new uri
      @logger.debug "getting attachment from uri #{uri}"
      request.basic_auth(@username, @password)
      response = Net::HTTP::start(uri.host, uri.port, use_ssl: true) do |http|
        http.request request
      end
      if response.is_a? Net::HTTPRedirection
        @logger.debug "redirecting to #{response['location']}"
        return get_attachment URI(response['location']), limit - 1
      end
      response.value
      response.body
    end

    # get all pages from a paged api and yield their parsed JSON body into a block
    def getpages(uri)
      pagenumber = 1
      loop do
        response = get uri
        body = JSON.parse(response.body)
        yield body, pagenumber
        next_page = body['next_page']
        break if next_page.nil?
        # If the next_page was the same as this one, it will loop forever
        next_uri = URI(next_page)
        break if uri == next_uri

        uri = next_uri
        pagenumber += 1
      end
    end

    def dumppages(uri, basepath, formatname)
      getpages uri do |page, pagenum|
        path = basepath + formatname % pagenum
        yield path, JSON.fast_generate(page)
      end
    end

    def dump_users(&block)
      uri = URI('https:/api/v2/users.json')
      uri.hostname = @domain
      getpages uri do |page|
        checkthreads(page['users']) do |user|
          begin
            dump_user(user['id'], &block)
          rescue Net::HTTPServerException
            @logger.error "could not find user #{user}"
          end
        end
      end
    end

    def dump_user(id, &block)
      # Get user meta details
      uri = URI("https:/api/v2/users/#{id}.json")
      uri.hostname = @domain
      response = get uri
      basepath = Pathname.new('users') + id.to_s
      yield basepath + 'user.json', response.body

      # Get user groups
      uri = URI("https:/api/v2/users/#{id}/groups.json")
      uri.hostname = @domain
      dumppages(uri, basepath, 'groups-%03d.json', &block)
    end

    def dump_organizations(&block)
      uri = URI('https:/api/v2/organizations.json')
      uri.hostname = @domain
      getpages uri do |page|
        checkthreads(page['organizations']) do |organization|
          begin
            dump_organization(organization['id'], &block)
          rescue Net::HTTPServerException
            @logger.error "could not find organization #{organization}"
          end
        end
      end
    end

    def dump_organization(id, &block)
      # get organization meta details
      uri = URI("https:/api/v2/organizations/#{id}.json")
      uri.hostname = @domain
      response = get uri
      basepath = Pathname.new('organizations') + id.to_s
      yield basepath + 'organization.json', response.body

      # Get users
      uri = URI("https:/api/v2/organizations/#{id}/users.json")
      uri.hostname = @domain
      dumppages(uri, basepath, 'users-%03d.json', &block)
    end

    def dump_tickets(&block)
      uri = URI('https:/api/v2/incremental/tickets.json?start_time=0')
      uri.hostname = @domain
      getpages uri do |page|
        checkthreads(page['tickets']) do |ticket|
          begin
            dump_ticket(ticket['id'], &block)
          rescue Net::HTTPServerException
            @logger.error "could not find ticket #{ticket}"
          end
        end
      end
    end

    def dump_ticket(id)
      # Yield base ticket details
      uri = URI("https:/api/v2/tickets/#{id}.json")
      uri.hostname = @domain
      response = get uri
      basepath = Pathname.new('tickets') + id.to_s
      yield basepath + 'ticket.json', response.body

      # Yield out all comments
      uri = URI("https:/api/v2/tickets/#{id}/comments.json")
      uri.hostname = @domain
      getpages uri do |page, pagenum|
        path = basepath + 'comments-%03d.json' % pagenum
        yield path, JSON.fast_generate(page)
        page['comments'].each do |comment|
          comment['attachments'].each do |attachment|
            basepath = Pathname.new('attachments') + attachment['id'].to_s
            @logger.debug "getting attachment json file"
            yield basepath + 'attachment.json', JSON.fast_generate(attachment)
            begin
              @logger.debug "getting attachment file #{basepath + 'files' + attachment['file_name']}"
              yield basepath + 'files' + attachment['file_name'], get_attachment(URI(attachment['content_url']))
            rescue Net::HTTPServerException
              @logger.error "could not find attachment file #{attachment}"
            end
          end
        end
      end
    end
  end
end

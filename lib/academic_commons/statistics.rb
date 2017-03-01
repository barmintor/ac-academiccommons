require 'csv'
require 'uri'
module AcademicCommons
  module Statistics
    include AcademicCommons::Listable

    VIEW = 'View '
    DOWNLOAD = 'Download '

    FACET_NAMES = Hash.new
    FACET_NAMES.store('author_facet', 'Author')
    FACET_NAMES.store('pub_date_facet', 'Date')
    FACET_NAMES.store('genre_facet', 'Content Type')
    FACET_NAMES.store('subject_facet', 'Subject')
    FACET_NAMES.store('type_of_resource_facet', 'Resource Type')
    FACET_NAMES.store('media_type_facet', 'Media Type')
    FACET_NAMES.store('organization_facet', 'Organization')
    FACET_NAMES.store('department_facet', 'Department')
    FACET_NAMES.store('series_facet', 'Series')
    FACET_NAMES.store('non_cu_series_facet', 'Non CU Series')

    private

    # Copied from Catalog Helper.
    # TODO: Needs to be in a more centralized place.
    def get_count(query_params)
      Blacklight.default_index.search(query_params)["response"]["numFound"]
    end

    def facet_names
      FACET_NAMES
    end

    # Return array of abbreviated month names.
    def months
      Array.new(Date::ABBR_MONTHNAMES).drop(1)
    end

    def log_statistics_usage(startdate, enddate, params)
      eventlog = Eventlog.create(
        event_name: 'statistics',
        user_name:  current_user == nil ? "N/A" : current_user.to_s,
        uid:        current_user == nil ? "N/A" : current_user.uid.to_s,
        ip:         request.remote_ip,
        session_id: request.session_options[:id]
      )

      eventlog.logvalues.create(:param_name => "startdate", :value => startdate.to_s)
      eventlog.logvalues.create(:param_name => "enddate", :value => enddate.to_s)
      eventlog.logvalues.create(:param_name => "commit", :value => params[:commit])
      eventlog.logvalues.create(:param_name => "search_criteria", :value => params[:search_criteria] )
      eventlog.logvalues.create(:param_name => "include_zeroes", :value => params[:include_zeroes] == nil ? "false" : "true")
      eventlog.logvalues.create(:param_name => "include_streaming_views", :value => params[:include_streaming_views] == nil ? "false" : "true")
      eventlog.logvalues.create(:param_name => "facet", :value => params[:facet])
      eventlog.logvalues.create(:param_name => "email_to", :value => params[:email_destination] == "email to" ? nil : params[:email_destination])
    end

    def make_test_author(author_id, email)
      [{ id: author_id, email: email }]
    end

    def school_pids(school)
      Blacklight.default_index.search(
        'qt' => "search", 'rows'=> 20000, 'facet.field'=>["pid"],
        'fq' => ["{!raw f=organization_facet}#{school}"]
      )["response"]["docs"]
    end

    def get_school_docs_size(school)
      query_params = {:qt=>"standard", :q=>'{!raw f=organization_facet}' + school}
      return get_count(query_params)
    end

    def facet_items(facet)
      query_params = {:q => "", :rows => 0, 'facet.limit' => -1, 'facet.field' => [facet]}
      solr_results = Blacklight.default_index.search(query_params)
      subjects = solr_results.facet_counts["facet_fields"][facet]

      results = [["" ,""]]

      res_item = {}
      subjects.each do |item|
        if(item.kind_of? Integer)
          res_item[:count] = item
          results << ["#{res_item[:name]} (#{res_item[:count]})", res_item[:name].to_s]
          res_item = {}
        else
          res_item[:name] = item
        end
      end

      results
    end

    def query_to_facets(query)
      facets_query = query.map do |param|
        facet = param[0]
        facet_item = param[1][0].to_s
        (facet_item.blank? || facet_item == 'undefined') ? nil : "{!raw f=#{facet}}#{facet_item}"
      end.compact
    end

    def get_pids_by_query_facets(query)
      query_params = {
        "qt" => "search", "rows" => 20000, "facet.field" => ["pid"],
        "fq" => query_to_facets(query)
      }
      Blacklight.default_index.search(query_params)["response"]["docs"]
    end

    def count_pids_statistic(pids_collection, event)
      Statistic.where("identifier in (?) and event = ?", collect_asset_pids(pids_collection, event), event).count
    end

    def count_pids_statistic_by_dates(pids_collection, event, startdate, enddate)
      Statistic.where("identifier in (?) and event = ? and at_time BETWEEN ? and ?", collect_asset_pids(pids_collection, event), event, startdate, enddate).count
    end

    def count_docs_by_event(pids_collection, event)
      Statistic.group(:identifier).where("identifier in (?) and event = ? ", collect_asset_pids(pids_collection, event), event).count
    end

    def count_docs_by_event_and_dates(pids_collection, event, startdate, enddate)
      Statistic.group(:identifier).where("identifier in (?) and event = ? and at_time BETWEEN ? and ? ", collect_asset_pids(pids_collection, event), event, startdate, enddate).count
    end

    # Maps a collection of Item/Aggregator PIDs to File/Asset PIDs
    def collect_asset_pids(pids_collection, event)
      pids_collection.map do |pid|
        pid[:id] ||= pid[:pid] # facet doc may be submitted with only pid value
        if(event == Statistic::DOWNLOAD_EVENT)
          most_downloaded_asset(pid) # Chooses most downloaded over lifetime.
        else
          pid[:id]
        end
      end.flatten.compact.uniq
    end

    # Most downloaded asset over entire lifetime.
    # Eventually may have to reevaluate this for queries that are for a specific
    # time range. For now, we are okay with this assumption.
    def most_downloaded_asset(pid)
      asset_pids = build_resource_list(pid).map { |doc| doc[:pid] }
      return asset_pids.first if asset_pids.count == 1

      # Get the higest value stored here.
      counts = Statistic.event_count(asset_pids, Statistic::DOWNLOAD_EVENT)

      # Return first pid, if items have never been downloaded.
      return asset_pids.first if counts.empty?

      # Get key of most downloaded asset.
      key, value = counts.max_by{ |_,v| v }
      key
    end

    def start_date(month, year)
      Date.parse("#{month} #{year}")
    end

    def end_date(month, year) # end_date needs to be last day of month
      date = Date.parse("#{month} #{year}")
      Date.new(date.year, date.month, -1)
    end

    def get_res_list
      query = params[:f]

      return [] if query.blank?

      start_date, end_date = nil, nil

      if params[:month_from] && params[:year_from] && params[:month_to] && params[:year_to]
        startdate = start_date(params[:month_from], params[:year_from])
        enddate = end_date(params[:month_to], params[:year_to])
      end

      solr_params = { fq: query_to_facets(query) }
      AcademicCommons::UsageStatistics.new(solr_params, startdate, enddate, include_streaming: true, order_by: 'title')
    end

    def get_docs_size_by_query_facets
      query = params[:f]

      if query == nil || query.empty?
        []
      else
        get_pids_by_query_facets(query)
      end
    end

    def get_facet_stats_by_event(query, event)
      if( query == nil || query.empty? )
        downloads = 0
        docs = Hash.new
      else
        pids_collection = get_pids_by_query_facets(query)

        if(params[:month_from] && params[:year_from] && params[:month_to] && params[:year_to] )
          startdate = Date.parse(params[:month_from] + " " + params[:year_from])
          enddate = Date.parse(params[:month_to] + " " + params[:year_to])
          count = count_pids_statistic_by_dates(pids_collection, event, startdate, enddate)
          docs = count_docs_by_event_and_dates(pids_collection, event, startdate, enddate)
        else
          count = count_pids_statistic(pids_collection, event)
          docs = count_docs_by_event(pids_collection, event)
        end
      end

      result = Hash.new
      result.store('docs_size', docs.size.to_s)
      result.store('statistic', count.to_s)
      result
    end

    def send_authors_reports(processed_authors, designated_recipient)
      start_time = Time.new
      time_id = start_time.strftime("%Y%m%d-%H%M%S")
      log_path = File.join(Rails.root, 'log', 'monthly_reports')
      logger = Logger.new(File.join(log_path, "#{time_id}.tmp"))

      logger.info "=== All Authors Monthly Reports ==="
      logger.info "Started at: " + start_time.strftime("%Y-%m-%d %H:%M")

      sent_counter = 0
      skipped_counter = 0
      sent_exceptions = 0

      processed_authors.each do |author|
        begin
          author_id = author[:id]
          startdate = Date.parse(params[:month] + " " + params[:year])
          enddate = Date.new(startdate.year, startdate.month, -1) # end_date needs to be last day of month

          solr_params = { q: nil, fq: "author_uni:\"#{author_id}\"" }
          usage_stats = AcademicCommons::UsageStatistics.new(
            solr_params, startdate, enddate, order_by: params[:order_by],
            include_zeroes: params[:include_zeroes], include_streaming: false,
          )

          email = designated_recipient || author[:email]
          raise "no email address found" if email.nil?

          if usage_stats.none?(&:zero?) || params[:include_zeroes]
            sent_counter += 1
            if(params[:do_not_send_email])
              test_msg = ' (this is test - email was not sent)'
            else
              Notifier.author_monthly(email, author_id, usage_stats, params[:optional_note]).deliver
              test_msg = ''
            end

            logger.info "Report for '#{author_id}' was sent to #{email} at " + Time.new.strftime("%Y-%m-%d %H:%M") + test_msg
          else
            skipped_counter += 1
            logger.info "Report for '#{author_id}' was skipped"
          end

        rescue Exception => e
          logger.error "For #{author_id}, email: #{author[:email]}"
          logger.error "#{e}\n\t#{e.backtrace.join("\n\t")}"
          sent_exceptions += 1
        end
      end

      finish_time = Time.new
      logger.info "Number of emails"
      logger.info "\tsent: #{sent_counter}, skipped: #{skipped_counter}, errors: #{sent_exceptions}"
      logger.info "Finished at: " + finish_time.strftime("%Y-%m-%d %H:%M")

      seconds_spent = finish_time - start_time
      readble_time_spent = Time.at(seconds_spent).utc.strftime("%H hours, %M minutes, %S seconds")

      logger.info "Time spent: #{readble_time_spent}"

      File.rename(File.join(log_path, "#{time_id}.tmp"), File.join(log_path, "#{time_id}.log"))
    end

    def clean_params(params)
      params[:one_report_uni] = nil
      params[:test_users] = nil
      params[:designated_recipient] = nil
      params[:one_report_email] = nil
    end

    def detail_report_solr_params(facet, query)
      Rails.logger.debug "In make_solr_request for query: #{query}"
      if facet == "search_query"
        solr_params = parse_search_query(query)
        facet_query = solr_params["f"]
        q = solr_params["q"]
        sort = solr_params["sort"]
      else
        facet_query = "#{facet}:\"#{query}\""
        sort = "title_display asc"
      end

      return if facet_query.nil? && q.nil?

      { sort: sort, q: q, fq: facet_query }
    end

    def parse_search_query(search_query)
      search_query = URI.unescape(search_query)
      search_query = search_query.gsub(/\+/, ' ')

      params = Hash.new

      if search_query.include? '?'
        search_query = search_query[search_query.index("?") + 1, search_query.length]
      end

      search_query.split('&').each do |value|
        key_value = value.split('=')

        if(key_value[0].start_with?("f[") )
          if(params.has_key?("f"))
            array = params["f"]
          else
            array = Array.new
          end

          value = key_value[0].gsub(/f\[/, '').gsub(/\]\[\]/, '') + ":\"" + key_value[1] + "\""
          array.push(value)
          params.store("f", array)
        else
          params.store(key_value[0], key_value[1])
        end
      end

      return params
    end
  end
end

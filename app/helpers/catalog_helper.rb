require 'cgi'
require 'rsolr'
require 'json'

module CatalogHelper
  include Blacklight::CatalogHelperBehavior
  include ApplicationHelper
  include AcademicCommons::Listable
  include AcademicCommons::Embargoes

  delegate :repository, :to => :controller

  # Adds handle or doi prefix if necessary. Makes field a clickable link.
  def link_identifier(**options)
    value = case options[:value]
            when /^(AC:P:\d+)$/
              "http://hdl.handle.net/10022/#{$1}"
            when /^(10.+)$/
              "http://dx.doi.org/#{$1}"
            else
              options[:value]
            end

    link_to value, value
  end

  def get_total_count
    date_trend.counts[:total]
  end

  def get_count_by_year
    date_trend.counts[:last_year]
  end

  def get_count_by_month
    date_trend.counts[:last_month]
  end

  def date_trend
    @date_trend ||= AcademicCommons::DateTrend.new("record_creation_date", ContentAggregator)
  end

  def build_recent_updated_list
    query_params = {
      :q => "", :fl => "title_display, id, author_facet, record_creation_date",
      :sort => "record_creation_date desc",
      :fq => ["author_facet:*", "has_model_ssim:\"#{ContentAggregator.to_class_uri}\""],
      :start => 0, :rows => 100}
    build_distinct_authors_list(query_params)
  end

  def build_distinct_authors_list(query_params, authors = [], results = [])
    response = repository.search(query_params)["response"]
    return results unless response["docs"].present?

    response["docs"].each do |r|
      new_authors = r["author_facet"] - authors if r["author_facet"]

      next unless new_authors.present?
      authors.concat new_authors
      results << r
      break if(results.length == blacklight_config[:max_most_recent])
    end
    more_items = query_params[:start] + query_params[:rows] < response["numFound"]
    if(results.length < blacklight_config[:max_most_recent] && more_items)
      query_params[:start] = query_params[:start] + query_params[:rows]
      build_distinct_authors_list(query_params, authors, results)
    else
      results
    end
  end

  # TODO: Move to a browse controller
  def collect_facet_field_values(facet_field_results)
    results = {}
    facet_field_results.each do |facet_field, facet_counts|
      results[facet_field] = (0...facet_counts.length/2).map do |ix|
        {name: facet_counts[ix * 2], count: facet_counts[1 + ix * 2]}
      end
    end
    results
  end

  # TODO: Move to a browse controller
  def single_facet_values(facet_field)
    query_params = {:q=>"", :rows=>"0", "facet.limit"=>-1, "facet.field" => facet_field}
    solr_results = repository.search(query_params)
    facet_field_results = solr_results.facet_counts["facet_fields"]
    collect_facet_field_values(facet_field_results).fetch(facet_field,[])
  end

  # TODO: Move to a browse controller
  def get_subjects_list
    single_facet_values("subject_facet")
  end

  # TODO: Move to a browse controller
  def get_departments_list
    single_facet_values("department_facet")
  end

  # TODO: Move to a browse controller
  def get_department_facet_list(department)
    query_params = {:q=>"", :'fq'=>"department_facet:\"" + department + "\"", :rows=>"0", "facet.limit"=>-1}
    solr_results = repository.search(query_params)
    facet_field_results = solr_results.facet_counts["facet_fields"]
    collect_facet_field_values(facet_field_results).delete_if do |k,v|
      k == "department_facet" || k == "organization_facet"
    end
  end

  def thumbnail_for_resource(resource)
    extension = get_file_extension(resource[:filename].to_s)
    thumbnail_folder_path = Rails.root.to_s + "/app/assets/images/thumbnail_icons/"
    if(!extension.nil? && !extension.empty?)
      thumbnail_file_name = extension + ".png"
    else
      thumbnail_file_name = [:content_type]
      thumbnail_file_name["/"] = "_"
      thumbnail_file_name += ".png"
    end

    if(!File.file?(thumbnail_folder_path + thumbnail_file_name))
      thumbnail_file_name = "default.png"
    end

    return thumbnail_file_name
  end

  def get_file_extension(filename)
    filename.to_s.split(".").last.strip
  end

  def doc_object_method(doc, method)
    doc["object_display"].first + method.to_s
  end

  def get_metadata_list(doc)
    #catch any error and return an error message that resources are unavailable
    #this prevents fedora server outages from making ac2 item page inaccessible
    begin
      #TODO: is this side effect on doc necessary?
      doc["object_display"] = [ "#{fedora_config["url"]}" + "/objects/" + doc["id"] + "/methods" ]
      results = doc["described_by_ssim"].map do |ds_uri|
        res = {}
        pid = ds_uri.split('/')[1]
        dsid = ds_uri.split('/')[2]
        # res[:id] = pid is not used
        # res[:title] = 'description' is not used
        # constant suffix for backwards compatibility with AC2
        filename = "#{pid.gsub(/\:/,"")}_description.xml"
        res[:show_url] = fedora_content_path(:show_pretty, pid, dsid, filename)
        res[:download_url] = fedora_content_path(:download, pid, dsid, filename)
        res
      end
    rescue => e
      Rails.logger.error "In get_metadata_list: #{e.message}"
      results = []
    end

    return results
  end

  ############### Copied from Blacklight CatalogHelper #####################

  # Pass in an RSolr::Response (or duck-typed similar) object,
  # it translates to a Kaminari-paginatable
  # object, with the keys Kaminari views expect.
  def paginate_params(response)
    per_page = response.rows
    per_page = 1 if per_page < 1
    current_page = (response.start / per_page).ceil + 1
    num_pages = (response.total / per_page.to_f).ceil
    Struct.new(:current_page, :num_pages, :limit_value, :total_pages).new(current_page, num_pages, per_page, num_pages)
  end

  # Equivalent to kaminari "paginate", but takes an RSolr::Response as first argument.
  # Will convert it to something kaminari can deal with (using #paginate_params), and
  # then call kaminari paginate with that. Other arguments (options and block) same as
  # kaminari paginate, passed on through.
  # will output HTML pagination controls.
  def paginate_rsolr_response(response, options = {}, &block)
    paginate paginate_params(response), options, &block
  end

  # Pass in an RSolr::Response. Displays the "showing X through Y of N" message.
  def render_pagination_info(response, options = {})
      page_info = paginate_params(response)

      start_num = number_with_delimiter(response.start + 1)
      end_num = number_with_delimiter(response.start + response.docs.length)
      total_num = number_with_delimiter(response.total)

      entry_name = options[:entry_name] ||
        (response.empty? ? 'entry' : response.docs.first.class.name.underscore.sub('_', ' '))

      if page_info.num_pages < 2
        case response.docs.length
        when 0; "No #{h(entry_name.pluralize)} found".html_safe
        when 1; "Displaying <b>1</b> #{h(entry_name)}".html_safe
        else;   "Displaying <b>all #{total_num}</b> #{entry_name.pluralize}".html_safe
        end
      else
        "Displaying #{h(entry_name.pluralize)} <b>#{start_num} - #{end_num}</b> of <b>#{total_num}</b>".html_safe
      end
  end

  # Like  #render_pagination_info above, but for an individual
  # item show page. Displays "showing X of Y items" message. Actually takes
  # data from session though (not a great design).
  # Code should call this method rather than interrogating session directly,
  # because implementation of where this data is stored/retrieved may change.
  def item_page_entry_info
    "Showing item <b>#{session[:search][:counter].to_i} of #{number_with_delimiter(session[:search][:total])}</b> from your search.".html_safe
  end

  # Look up search field user-displayable label
  # based on params[:qt] and configuration.
  def search_field_label(params)
    if(params[:search_field].blank?)
      h( "Keyword" )
    else
      h( Blacklight.label_for_search_field(params[:search_field]) )
    end
  end

  # Export to Refworks URL, called in _show_tools
  def refworks_export_url(document = @document)
    "http://www.refworks.com/express/expressimport.asp?vendor=#{CGI.escape(application_name)}&filter=MARC%20Format&encoding=65001&url=#{CGI.escape(catalog_path(document.id, :format => 'refworks_marc_txt', :only_path => false))}"
  end

  def render_document_class(document = @document)
   'blacklight-' + document.get(blacklight_config[:index][:record_display_type]).parameterize rescue nil
  end

  def render_document_sidebar_partial(document = @document)
    render :partial => 'show_sidebar'
  end

  def pdf_urls
    urls = []
    if(@document != nil)
      resource_list = build_resource_list(@document)
      resource_list.each do |resource|
           urls.push( "http://" + request.host_with_port + resource[:download_path] )
       end
     end
     return urls
  end

  def itemscope_itemtype
    url_from_map = blacklight_config[:itemscope][:itemtypes][@document["genre_facet"]]
    if url_from_map.nil?
      "http://schema.org/CreativeWork"
    else
      url_from_map
    end
  end

  def render_document_class(document = @document)
    'blacklight-' + document.get(blacklight_config.view_config(document_index_view_type_field).display_type_field).parameterize rescue nil
  end

  def facet_list_limit
    10
  end

  # Overriding Blacklight helper method.
  #
  # Standard display of a SELECTED facet value, no link, special span
  # with class, and 'remove' button.
  def render_selected_facet_value(facet_solr_field, item)
    render = link_to((item.value + render_facet_count(item.hits)).html_safe, search_action_path(remove_facet_params(facet_solr_field, item.value, params)), :class=>"facet_deselect")
    render = render + render_subfacets(facet_solr_field, item)
    render.html_safe
  end

  def render_subfacets(facet_solr_field, item, options ={})
    render = ''
    if (item.instance_variables.include? "@subfacets")
      render = '<span class="toggle">[+/-]</span><ul>'
      item.subfacets.each do |subfacet|
        if facet_in_params?(facet_solr_field, subfacet.value)
          render += '<li>' + render_selected_facet_value(facet_solr_field, subfacet) + '</li>'
        else
          render += '<li>' + render_facet_value(facet_solr_field, subfacet,options) + '</li>'
        end
      end
      render += '</ul>'
    end
    render.html_safe
  end
end
